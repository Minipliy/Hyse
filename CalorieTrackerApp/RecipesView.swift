import SwiftUI
import UIKit

private enum RecipePropertyGroup: CaseIterable {
    case diet, ingredients, dietaryNeeds, nutrition, meal

    var titleKey: String {
        switch self {
        case .diet: "recipes.filter_group_diet"
        case .ingredients: "recipes.filter_group_ingredients"
        case .dietaryNeeds: "recipes.filter_group_dietary_needs"
        case .nutrition: "recipes.filter_group_nutrition"
        case .meal: "edit_entry.meal"
        }
    }

    var filters: [RecipeFilter] {
        switch self {
        case .diet: [.vegan, .vegetarian, .pescetarian, .carnivore]
        case .ingredients: [.fish, .meat]
        case .dietaryNeeds: [.glutenFree, .lactoseFree]
        case .nutrition: [.highProtein, .lowSugar, .lowCalorie]
        case .meal: RecipeFilter.meals
        }
    }

    static func ordered(_ filters: Set<RecipeFilter>) -> [RecipeFilter] {
        allCases.flatMap(\.filters).filter(filters.contains)
    }
}

struct RecipesView: View {
    @EnvironmentObject private var language: LanguageStore
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var mealPlan: MealPlanStore
    @EnvironmentObject private var categoryStore: CategoryStore
    @EnvironmentObject private var calorieStore: CalorieStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObservedObject var foodStore: FoodStore
    @ObservedObject var recipeStore: RecipeStore
    @ObservedObject var frequencyStore: FrequencyStore
    var onChooseForEntry: ((Recipe, Double) -> Void)? = nil
    @State private var editorRecipe: Recipe?
    @State private var selectedRecipe: Recipe?
    @State private var pendingEntryChoice: (recipe: Recipe, servings: Double)?
    @State private var showingNew = false
    @State private var searchText = ""
    @State private var selectedFilters: Set<RecipeFilter> = []
    @State private var sortByCalories = false
    @State private var favoritesOnly = false
    @State private var showingFilters = false
    @State private var recipeScope = 0
    @State private var favoriteActionsInFlight: Set<UUID> = []
    @State private var recipeToDelete: Recipe?
    private func t(_ key: String, _ arguments: CVarArg...) -> String { language.text(key, arguments) }

    private var filteredRecipes: [Recipe] {
        (recipeScope == 0 ? recipeStore.recipes : recipeStore.globalRecipes)
            .filter {
                searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText)
                    || $0.recipeDescription.localizedCaseInsensitiveContains(searchText)
                    || $0.tags.contains { $0.localizedCaseInsensitiveContains(searchText) }
            }
            .filter { selectedFilters.isSubset(of: $0.filters) }
            .filter { !favoritesOnly || isFavorite($0) }
            .sorted { sortByCalories ? $0.caloriesPerServing < $1.caloriesPerServing : frequencyStore.totalUsageCount(itemId: $0.id) == frequencyStore.totalUsageCount(itemId: $1.id) ? $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending : frequencyStore.totalUsageCount(itemId: $0.id) > frequencyStore.totalUsageCount(itemId: $1.id) }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: HyseSpacing.medium) {
                    Picker(t("recipes.source"), selection: $recipeScope) {
                        Text(t("recipes.my_recipes")).tag(0)
                        Text(t("recipes.global_recipes")).tag(1)
                    }
                    .pickerStyle(.segmented)
                    HStack(spacing: HyseSpacing.medium) {
                        HyseSearchField(placeholder: t("recipes.search_recipes"), text: $searchText)
                        Button { favoritesOnly.toggle() } label: {
                            Image(systemName: favoritesOnly ? "star.fill" : "star")
                                .font(.body.weight(.medium))
                                .foregroundStyle(favoritesOnly ? HyseColor.warning : .primary)
                                .frame(width: 44, height: 44)
                                .background(HyseColor.surface, in: RoundedRectangle(cornerRadius: HyseRadius.control))
                                .overlay(RoundedRectangle(cornerRadius: HyseRadius.control).stroke(HyseColor.border))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(t("recipes.favorites_only"))
                        .accessibilityAddTraits(favoritesOnly ? .isSelected : [])
                        Button { showingFilters = true } label: {
                            Image(systemName: "line.3.horizontal.decrease")
                                .font(.body.weight(.medium))
                                .foregroundStyle(.primary)
                                .frame(width: 44, height: 44)
                                .background(HyseColor.surface, in: RoundedRectangle(cornerRadius: HyseRadius.control))
                                .overlay(RoundedRectangle(cornerRadius: HyseRadius.control).stroke(HyseColor.border))
                                .overlay(alignment: .topTrailing) {
                                    let count = selectedFilters.count + (sortByCalories ? 1 : 0) + (favoritesOnly ? 1 : 0)
                                    if count > 0 {
                                        Text("\(count)")
                                            .font(.caption2.weight(.bold))
                                            .foregroundStyle(.primary)
                                            .padding(5)
                                            .background(HyseColor.elevatedSurface, in: Circle())
                                            .offset(x: 5, y: -5)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(t("recipes.filter_recipes"))
                    }
                    Text(t("recipes.recipe_count", filteredRecipes.count))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .listRowInsets(EdgeInsets(top: HyseSpacing.medium, leading: HyseSpacing.page, bottom: HyseSpacing.medium, trailing: HyseSpacing.page))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            if recipeScope == 0, recipeStore.syncState == .offline || recipeStore.syncState == .failed {
                HyseStatusBanner(title: t("recipes.sync_pending"), message: t("recipes.sync_pending_detail"), style: .warning, actionTitle: t("content.retry"), action: recipeStore.syncPendingRecipes)
            }
            if !selectedFilters.isEmpty || favoritesOnly || sortByCalories {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(RecipePropertyGroup.ordered(selectedFilters)) { filter in
                                Button {
                                    selectedFilters.remove(filter)
                                } label: {
                                    Label(filter.title, systemImage: "xmark")
                                        .font(.caption.weight(.medium))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 6)
                                        .foregroundStyle(.primary)
                                        .background(Color.primary.opacity(0.08), in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                            if sortByCalories {
                                Button { sortByCalories = false } label: {
                                    Label(t("recipes.sort_by_kcal_per_serving"), systemImage: "xmark")
                                        .font(.caption.weight(.medium))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 6)
                                        .foregroundStyle(.primary)
                                        .background(Color.primary.opacity(0.08), in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                            if favoritesOnly {
                                Button { favoritesOnly = false } label: {
                                    Label(t("recipes.favorites_only"), systemImage: "xmark")
                                        .font(.caption.weight(.medium))
                                        .padding(.horizontal, 8).padding(.vertical, 6)
                                        .foregroundStyle(.primary)
                                        .background(Color.primary.opacity(0.08), in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                            Button(t("recipes.clear_all")) { resetFilters() }
                                .font(.caption.weight(.semibold))
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 0, leading: HyseSpacing.page, bottom: HyseSpacing.small, trailing: HyseSpacing.page))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            if filteredRecipes.isEmpty {
                HyseEmptyState(
                    icon: "book.closed",
                    title: isUnfiltered ? t("recipes.no_recipes_yet") : t("recipes.no_matching_recipes"),
                    message: isUnfiltered ? t(recipeScope == 0 ? "recipes.empty_library_message" : "recipes.empty_global_message") : t("recipes.adjust_search_filters"),
                    actionTitle: recipeScope == 0 && isUnfiltered ? t("recipe_editor.create_recipe") : nil,
                    action: recipeScope == 0 && isUnfiltered ? { showingNew = true } : nil
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            ForEach(filteredRecipes) { recipe in
                Button { selectedRecipe = recipe } label: {
                        RecipeLibraryCard(recipe: recipe, status: recipeStatusText(recipe), favorite: isFavorite(recipe), highlightedFilters: selectedFilters)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(recipe.name)
                .accessibilityHint(t("recipes.open_details"))
                .listRowInsets(EdgeInsets(top: 4, leading: HyseSpacing.page, bottom: 4, trailing: HyseSpacing.page))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .contextMenu {
                    Button { toggleFavoriteOnce(recipe) } label: {
                        Label(t(isFavorite(recipe) ? "add_entry.remove_from_favorites" : "add_entry.add_favorites"), systemImage: isFavorite(recipe) ? "star.slash" : "star")
                    }
                    if recipe.origin == .personal {
                        Button { editorRecipe = recipe } label: { Label(t("recipe_editor.edit_recipe"), systemImage: "pencil") }
                    }
                    if recipe.origin == .personal, authManager.isLoggedIn {
                        Button { recipeStore.submitGlobally(id: recipe.id) } label: { Label(t("recipes.submit_global"), systemImage: "globe.europe.africa") }
                    } else if recipe.origin == .global {
                        Button { recipeStore.saveGlobalRecipe(recipe) } label: { Label(t("recipes.save_to_my_recipes"), systemImage: "square.and.arrow.down") }
                    }
                    if recipe.origin == .personal {
                        Button(role: .destructive) { recipeToDelete = recipe } label: { Label(t("settings.delete"), systemImage: "trash") }
                    }
                }
            }
            .onDelete { offsets in if recipeScope == 0 { recipeToDelete = offsets.first.map { filteredRecipes[$0] } } }
        }
        .hyseForm()
        .listStyle(.plain)
        .navigationTitle(t("recipes.recipes"))
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink {
                    MealPlanView(plan: mealPlan, recipes: recipeStore, categories: categoryStore, calories: calorieStore)
                } label: { Label(t("meal_plan.title"), systemImage: "calendar") }
            }
            if recipeScope == 0 { ToolbarItem(placement: .navigationBarTrailing) { Button { showingNew = true } label: { Label(t("recipe_editor.create_recipe"), systemImage: "plus") } } }
        }
        .sheet(isPresented: $showingNew) { RecipeEditorView(foodStore: foodStore, recipeStore: recipeStore) }
        .sheet(item: $editorRecipe) { RecipeEditorView(foodStore: foodStore, recipeStore: recipeStore, recipe: $0) }
        .sheet(item: $selectedRecipe, onDismiss: {
            if let pendingEntryChoice {
                self.pendingEntryChoice = nil
                onChooseForEntry?(pendingEntryChoice.recipe, pendingEntryChoice.servings)
            }
        }) {
            RecipeDetailsView(
                recipe: $0,
                foodStore: foodStore,
                recipeStore: recipeStore,
                onChooseForEntry: onChooseForEntry == nil ? nil : { recipe, servings in
                    pendingEntryChoice = (recipe, servings)
                    selectedRecipe = nil
                }
            )
        }
        .confirmationDialog(t("recipes.delete_title"), isPresented: Binding(get: { recipeToDelete != nil }, set: { if !$0 { recipeToDelete = nil } })) {
            Button(t("settings.delete"), role: .destructive) {
                if let recipeToDelete { recipeStore.delete(id: recipeToDelete.id) }
                recipeToDelete = nil
            }
        } message: { Text(t("recipes.delete_message")) }
        .task { recipeStore.syncPendingRecipes() }
        .sheet(isPresented: $showingFilters) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: HyseSpacing.large) {
                        Text(RecipePropertyGroup.allCases.map { t($0.titleKey) }.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Toggle(isOn: $sortByCalories) {
                            Label(t("recipes.sort_by_kcal_per_serving"), systemImage: "arrow.up.arrow.down")
                                .font(.subheadline.weight(.medium))
                        }
                        .tint(HyseColor.accent)
                        .padding(.horizontal, HyseSpacing.large)
                        .frame(minHeight: 44)
                        .background(HyseColor.surface, in: RoundedRectangle(cornerRadius: HyseRadius.control))
                        .overlay(RoundedRectangle(cornerRadius: HyseRadius.control).stroke(HyseColor.border))

                        ForEach(RecipePropertyGroup.allCases, id: \.self) { group in
                            filterSection(t(group.titleKey), filters: group.filters)
                        }
                    }
                    .padding(.horizontal, HyseSpacing.page)
                    .padding(.vertical, HyseSpacing.medium)
                }
                .background(HyseBackdrop())
                .navigationTitle(t("recipes.filter_recipes"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if !selectedFilters.isEmpty || sortByCalories || favoritesOnly {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(t("recipes.clear_all")) { resetFilters() }
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(t("add_entry.done")) { showingFilters = false }
                    }
                }
            }
            .presentationDetents([.large])
        }
    }

    @ViewBuilder private func filterSection(_ title: String, filters: [RecipeFilter]) -> some View {
        VStack(alignment: .leading, spacing: HyseSpacing.small) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            LazyVGrid(columns: dynamicTypeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.flexible()), GridItem(.flexible())], spacing: HyseSpacing.small) {
                ForEach(filters) { filter in
                    let selected = selectedFilters.contains(filter)
                    Button {
                        if selected { selectedFilters.remove(filter) }
                        else { selectedFilters.insert(filter) }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selected ? HyseColor.accent : Color.secondary)
                            Text(filter.title)
                                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                                .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.85)
                            Spacer(minLength: 0)
                        }
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .padding(.horizontal, HyseSpacing.medium)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .background(selected ? HyseColor.accent.opacity(0.13) : HyseColor.surface, in: RoundedRectangle(cornerRadius: HyseRadius.control))
                        .overlay(RoundedRectangle(cornerRadius: HyseRadius.control).stroke(selected ? HyseColor.accent : HyseColor.border))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .accessibilityHint(t("recipes.turn_filter_on_off"))
                }
            }
        }
    }

    private func resetFilters() { selectedFilters.removeAll(); sortByCalories = false; favoritesOnly = false }
    private var isUnfiltered: Bool { searchText.isEmpty && selectedFilters.isEmpty && !favoritesOnly }
    private func isFavorite(_ recipe: Recipe) -> Bool {
        recipe.origin == .global ? recipeStore.isGlobalFavorite(recipe) : recipe.isFavorite
    }

    private func toggleFavoriteOnce(_ recipe: Recipe) {
        guard favoriteActionsInFlight.insert(recipe.id).inserted else { return }
        if recipe.origin == .global { recipeStore.toggleGlobalFavorite(recipe) }
        else { var update = recipe; update.isFavorite.toggle(); recipeStore.update(update) }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            favoriteActionsInFlight.remove(recipe.id)
        }
    }

    private func recipeStatusText(_ recipe: Recipe) -> String? {
            if recipe.origin == .global { return nil }
            if let status = recipe.moderationStatus {
                switch status {
                case .pending: return t("recipes.moderation_pending")
                case .approved: return nil
                case .rejected: return t("recipes.moderation_rejected")
                }
            }
            switch recipe.syncStatus {
            case .local: return t("recipes.sync_local")
            case .pendingSync: return t("recipes.sync_pending_sync")
            case .synced: return nil
            case .failed: return t("recipes.sync_failed")
            case .conflict: return t("recipes.sync_conflict")
            }
    }
}

struct RecipeLibraryCard: View {
    @EnvironmentObject private var language: LanguageStore
    let recipe: Recipe
    var status: String? = nil
    var favorite = false
    var highlightedFilters: Set<RecipeFilter> = []

    private var properties: String {
        let ordered = RecipePropertyGroup.ordered(recipe.filters)
        let matching = ordered.filter(highlightedFilters.contains)
        let remainingProperties = ordered.filter { !highlightedFilters.contains($0) }
        let prioritized = matching + remainingProperties
        let visibleCount = max(2, matching.count)
        let names = prioritized.prefix(visibleCount).map(\.title).joined(separator: " · ")
        let remaining = prioritized.count - visibleCount
        return remaining > 0 ? "\(names) · +\(remaining)" : names
    }

    var body: some View {
        HyseCard { summary }
    }

    private var summary: some View {
        HStack(alignment: .center, spacing: HyseSpacing.large) {
            Group {
                if let data = RecipeImageStore.data(for: recipe.imageFileName)
                    ?? RecipeImageStore.cachedRemoteData(remoteID: recipe.remoteID, fileName: recipe.remoteImageFileName),
                   let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Image(systemName: "fork.knife").font(.body.weight(.medium)).foregroundStyle(.secondary)
                }
            }
            .frame(width: 56, height: 56)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: HyseRadius.small))
            .clipShape(RoundedRectangle(cornerRadius: HyseRadius.small))
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: HyseSpacing.small) {
                    Text(recipe.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    if favorite {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(HyseColor.warning)
                    }
                }
                Text(metadata)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let status {
                    Text(status)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if !properties.isEmpty {
                    Text(properties)
                        .font(.caption2)
                        .foregroundStyle(HyseColor.accentStrong)
                        .lineLimit(highlightedFilters.count > 2 ? 2 : 1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var metadata: String {
        let portions = language.text("recipes.portions_value", [String(Int(recipe.servings))])
        var values = ["\(Int(recipe.caloriesPerServing)) kcal", portions]
        if let minutes = recipe.preparationMinutes, minutes > 0 {
            values.append("\(minutes) \(language.text("recipes.minutes"))")
        }
        return values.joined(separator: " · ")
    }
}

struct RecipeFilterBadges: View {
    @EnvironmentObject private var language: LanguageStore
    let filters: Set<RecipeFilter>
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(RecipePropertyGroup.allCases, id: \.self) { group in
                let names = group.filters.filter(filters.contains).map(\.title)
                if !names.isEmpty {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(language.text(group.titleKey))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 96, alignment: .leading)
                        Text(names.joined(separator: " · "))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

struct CategoryEditView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var language: LanguageStore
    @ObservedObject var categoryStore: CategoryStore
    private let category: MealCategory
    @State private var name = ""
    @State private var targetPercentage = ""
    @State private var targetCalories = ""
    @State private var limitPercentage = ""
    @State private var limitCalories = ""
    @State private var enforce = false
    private func t(_ key: String, _ arguments: CVarArg...) -> String { language.text(key, arguments) }
    init(categoryStore: CategoryStore, category: MealCategory) {
        self.categoryStore = categoryStore; self.category = category
        _name = State(initialValue: category.localizedName)
        _targetPercentage = State(initialValue: category.targetPercentage.map { String(format: "%.0f", $0) } ?? "")
        _targetCalories = State(initialValue: category.targetCalories.map { String(format: "%.0f", $0) } ?? "")
        _limitPercentage = State(initialValue: category.limitPercentage.map { String(format: "%.0f", $0) } ?? "")
        _limitCalories = State(initialValue: category.limitCalories.map { String(format: "%.0f", $0) } ?? "")
        _enforce = State(initialValue: category.enforceLimit)
    }
    var body: some View {
        NavigationStack {
            Form(content: {
                Section(header: Text("ui.category")) {
                    TextField("ui.meal_name_e_g_breakfast", text: $name)
                }
                Section(
                    header: Text(t("recipes.guidance_value")),
                    footer: Text(t("recipes.guidance_value_explanation"))
                ) {
                    measurementField(title: t("recipes.share_daily_goal"), placeholder: t("recipes.example_30"), value: $targetPercentage, unit: "%")
                    measurementField(title: t("recipes.fixed_daily_value"), placeholder: t("recipes.example_600"), value: $targetCalories, unit: "kcal")
                }
                Section(
                    header: Text(t("recipes.maximum_calorie_limit")),
                    footer: Text("ui.limit_applies_only_when_enabled_percentage_takes")
                ) {
                    Toggle(t("recipes.enforce_calorie_limit"), isOn: $enforce)
                    measurementField(title: t("recipes.share_daily_goal"), placeholder: t("recipes.example_35"), value: $limitPercentage, unit: "%")
                    measurementField(title: t("recipes.fixed_limit"), placeholder: t("recipes.example_700"), value: $limitCalories, unit: "kcal")
                }
            })
            .hyseForm()
            .navigationTitle("ui.edit_category")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("app_tabs.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("recipe_editor.save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
    private func measurementField(title: String, placeholder: String, value: Binding<String>, unit: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(placeholder, text: value)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
            Text(unit).foregroundStyle(.secondary)
        }
    }
    private func number(_ value: String) -> Double? { let result = Double(value); return (result ?? 0) > 0 ? result : nil }
    private func save() {
        var updated = category
        let editedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if editedName != category.localizedName {
            updated.name = editedName
            updated.systemKey = nil
        }
        updated.targetPercentage = number(targetPercentage)
        updated.targetCalories = number(targetCalories)
        updated.limitPercentage = number(limitPercentage)
        updated.limitCalories = number(limitCalories)
        updated.enforceLimit = enforce
        categoryStore.updateCategory(updated)
        dismiss()
    }
}
