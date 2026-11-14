import SwiftUI

struct SavedFoodsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var language: LanguageStore
    @ObservedObject var foodStore: FoodStore
    @State private var searchText = ""
    @State private var selectedFood: FoodItem?
    @State private var editingFood: FoodItem?
    @State private var foodToDelete: FoodItem?
    @State private var showingDeleteAlert = false
    @State private var favoriteActionsInFlight: Set<UUID> = []

    var filteredFoods: [FoodItem] {
        foodStore.searchFoods(query: searchText, includeGlobals: false)
    }

    var body: some View {
        VStack {
            HyseSearchField(placeholder: language.text("saved_foods.search_foods"), text: $searchText)
            .padding(.horizontal)
            .padding(.top, 8)

            List {
                Section {
                    syncStatus
                }
                .hyseGlassListRows(accent: HyseColor.accent)

                ForEach(filteredFoods) { food in
                    HStack(spacing: 8) {
                        Button { selectedFood = food } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(food.displayName(using: language))
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                if let status = food.globalModerationStatus {
                                    Label(
                                        status == .pending ? language.text("saved_foods.changes_being_reviewed") : status == .approved ? language.text("saved_foods.available_globally") : language.text("saved_foods.change_rejected"),
                                        systemImage: status == .pending ? "clock.badge" : status == .approved ? "globe.europe.africa.fill" : "xmark.shield"
                                    )
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(status == .pending ? HyseColor.warning : status == .approved ? HyseColor.success : HyseColor.danger)
                                }
                                Text(nutritionSummary(for: food))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(food.displayName(using: language))

                        Button { editingFood = food } label: {
                            Image(systemName: "pencil")
                                .foregroundStyle(HyseColor.accent)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(language.text("ui.edit_food"))

                        Button { toggleFavoriteOnce(food) } label: {
                            Image(systemName: foodStore.isFavorite(food) ? "star.fill" : "star")
                                .foregroundStyle(foodStore.isFavorite(food) ? HyseColor.warning : .secondary)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .disabled(favoriteActionsInFlight.contains(food.id))
                        .accessibilityLabel(language.text(foodStore.isFavorite(food) ? "add_entry.remove_from_favorites" : "add_entry.add_favorites"))
                    }
                    .hyseGlassListRows()
                }
                .onDelete { offsets in
                    if let index = offsets.first {
                        foodToDelete = filteredFoods[index]
                        showingDeleteAlert = true
                    }
                }
            }
            .listStyle(.insetGrouped)
            .hyseForm()
            .overlay {
                if filteredFoods.isEmpty && !searchText.isEmpty {
                    HyseEmptyState(
                        icon: "magnifyingglass",
                        title: language.text("saved_foods.nothing_found"),
                        message: language.text("saved_foods.check_search_create_new_food")
                    )
                    .padding(HyseSpacing.page)
                    .hyseGlassSurface(radius: HyseRadius.card)
                    .padding(HyseSpacing.page)
                }
            }
        }
        .navigationTitle("ui.saved_foods")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editingFood) { food in
            EditFoodView(foodStore: foodStore, foodItem: food)
        }
        .sheet(item: $selectedFood) { food in
            NavigationStack {
                Form {
                    Section {
                        LabeledContent("ui.calories", value: "\(Int(food.kcalPerNutritionReference)) kcal")
                        LabeledContent("ui.carbohydrates", value: String(format: "%.1f g", food.carbsPerNutritionReference))
                        LabeledContent("ui.protein", value: String(format: "%.1f g", food.proteinPerNutritionReference))
                        LabeledContent("ui.fat", value: String(format: "%.1f g", food.fatPerNutritionReference))
                    } header: { Text(language.text("create_food.per_reference_unit", [String(Int(food.unit.nutritionReferenceAmount)), food.unit.rawValue])) }
                }
                .hyseForm()
                .navigationTitle(food.displayName(using: language))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("add_entry.done") { selectedFood = nil } } }
            }
        }
        .alert("ui.delete_food", isPresented: $showingDeleteAlert) {
            Button("app_tabs.cancel", role: .cancel) {
                foodToDelete = nil
            }
            Button("settings.delete", role: .destructive) {
                if let food = foodToDelete {
                    foodStore.deleteFood(id: food.id)
                }
                foodToDelete = nil
            }
        } message: {
            Text("ui.do_you_really_want_delete_food_existing")
        }
    }

    private func toggleFavoriteOnce(_ food: FoodItem) {
        guard favoriteActionsInFlight.insert(food.id).inserted else { return }
        foodStore.toggleFavorite(food)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            favoriteActionsInFlight.remove(food.id)
        }
    }

    private func nutritionSummary(for food: FoodItem) -> String {
        String(
            format: "%d kcal / %@ • C: %.1f g P: %.1f g F: %.1f g",
            Int(food.kcalPerNutritionReference),
            food.unit.nutritionReferenceLabel,
            food.carbsPerNutritionReference,
            food.proteinPerNutritionReference,
            food.fatPerNutritionReference
        )
    }

    @ViewBuilder
    private var syncStatus: some View {
        switch foodStore.syncState {
        case .idle:
            HyseStatusBanner(title: nil, message: language.text("saved_foods.saved_on_device"), style: .information)
        case .syncing:
            HStack {
                ProgressView()
                Text(language.text("saved_foods.syncing_hyse_account"))
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        case .synced:
            HyseStatusBanner(title: nil, message: language.text("saved_foods.synced_hyse_account"), style: .success)
        case .waitingToRetry:
            HyseStatusBanner(
                title: nil,
                message: language.text("saved_foods.retrying_automatically"),
                style: .information,
                actionTitle: language.text("saved_foods.try_again"),
                action: foodStore.syncPendingFoods
            )
        case .offline:
            HyseStatusBanner(
                title: language.text("content.offline"),
                message: language.text("saved_foods.unable_sync_right_now"),
                style: .offline,
                actionTitle: language.text("saved_foods.try_again"),
                action: foodStore.syncPendingFoods
            )
        }
    }
}
