import SwiftUI
import AVFoundation
import UIKit

private struct PendingFoodEntry: Identifiable, Codable {
    let id: UUID
    var entry: CalorieEntry
    let food: FoodItem?
    var amountText: String
    let usesPortion: Bool

    init(entry: CalorieEntry, food: FoodItem?, amountText: String, usesPortion: Bool) {
        self.id = entry.id
        self.entry = entry
        self.food = food
        self.amountText = amountText
        self.usesPortion = usesPortion
    }
}

/// Foods in the review list have not been committed to the daily log yet.
/// Keep this tiny draft locally so closing the app cannot silently discard a
/// list the user still wants to check before submitting.
private struct PendingFoodEntryDraft: Codable {
    var categoryID: UUID
    var entryDate: Date
    var entries: [PendingFoodEntry]
    var isReviewing: Bool
}

struct AddEntryView: View {
    private enum PortionFraction: CaseIterable, Identifiable, Hashable {
        case none, eighth, quarter, third, half, twoThirds, threeQuarters, sevenEighths

        var id: Double { value }
        var value: Double {
            switch self {
            case .none: 0
            case .eighth: 1.0 / 8.0
            case .quarter: 1.0 / 4.0
            case .third: 1.0 / 3.0
            case .half: 1.0 / 2.0
            case .twoThirds: 2.0 / 3.0
            case .threeQuarters: 3.0 / 4.0
            case .sevenEighths: 7.0 / 8.0
            }
        }
        var label: String {
            switch self {
            case .none: "–"
            case .eighth: "⅛"
            case .quarter: "¼"
            case .third: "⅓"
            case .half: "½"
            case .twoThirds: "⅔"
            case .threeQuarters: "¾"
            case .sevenEighths: "⅞"
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var language: LanguageStore
    @EnvironmentObject private var accountData: AccountDataStore
    @EnvironmentObject private var premium: PremiumAccessStore
    @ObservedObject var foodStore: FoodStore
    @ObservedObject var recipeStore: RecipeStore
    @ObservedObject var categoryStore: CategoryStore
    @ObservedObject var frequencyStore: FrequencyStore
    @ObservedObject var userSettings: UserSettingsStore
    @ObservedObject var calorieStore: CalorieStore
    let availableCalories: Double
    let foodSelectionHandler: ((FoodItem) -> Void)?
    let dismissAfterFoodSelection: Bool
    @State private var selectedEntryDate: Date
    @State private var selectedCategory: MealCategory
    @State private var filter = 1
    @State private var query = ""
    @State private var selectedFood: FoodItem?
    @State private var selectedRecipe: Recipe?
    @State private var amount = "100"
    @State private var recipeUnit = 0
    @State private var recipeQuantity = "1"
    /// 0 = Menge in g/ml eingeben, 1 = Anzahl Portionen (nur wenn das Lebensmittel eine Portionsgröße hat)
    @State private var foodAmountMode = 0
    @State private var selectedPortionID: UUID?
    @State private var showingRecipeEditor = false
    @State private var showingRecipes = false
    @State private var editingFood: FoodItem?
    @State private var alertMessage: String?
    @State private var isSaving = false
    @State private var showingQuickEntry = false
    @State private var showingLocalFoodAnalysis = false
    @State private var showingNutritionPremium = false
    @State private var favoriteActionsInFlight: Set<UUID> = []
    @State private var visibleFoods: [FoodItem] = []
    @State private var isPreparingFoodResults = true
    @State private var isSearchingRemoteFoods = false
    @State private var showingCalorieGoalWarning = false
    @State private var calorieGoalOverage = 0
    @State private var pendingEntries: [PendingFoodEntry] = []
    @State private var reviewingPendingEntries = false
    @FocusState private var searchFocused: Bool
    @FocusState private var amountFocused: Bool

    private func t(_ key: String, _ arguments: CVarArg...) -> String { language.text(key, arguments) }

    @State private var showingCreateFoodSheet = false
    @State private var showingBarcodeScanner = false
    @State private var scannedBarcodeForNewFood = ""
    @State private var scannedExternalDraft: FoodItem?
    @State private var newFoodInitialName = ""
    @State private var isLoadingBarcode = false
    @State private var barcodeStatusKey = "barcode.checking_hyse"
    @State private var showingCameraExplanation = false
    @State private var showingCameraDenied = false
    @State private var showingManualBarcode = false
    @State private var manualBarcode = ""
    @State private var scannerTorchOn = false
    @State private var scannerShowsManualEntry = false
    @State private var scannerCreationReady = false
    @State private var recentSearchedFoodKeys: [String]

    private static let recentSearchedFoodsKey = "recent_searched_food_ids_v1"
    private static let stableRecentSearchedFoodsKey = "recent_searched_food_keys_v2"
    private static let pendingDraftKey = "add_entry_pending_food_draft_v1"

    init(foodStore: FoodStore, recipeStore: RecipeStore, categoryStore: CategoryStore, frequencyStore: FrequencyStore, userSettings: UserSettingsStore, calorieStore: CalorieStore, availableCalories: Double, category: MealCategory, entryDate: Date, foodSelectionHandler: ((FoodItem) -> Void)? = nil, dismissAfterFoodSelection: Bool = true) {
        self.foodStore = foodStore; self.recipeStore = recipeStore; self.categoryStore = categoryStore; self.frequencyStore = frequencyStore; self.userSettings = userSettings; self.calorieStore = calorieStore; self.availableCalories = availableCalories; self.foodSelectionHandler = foodSelectionHandler; self.dismissAfterFoodSelection = dismissAfterFoodSelection
        let committedIDs = Set(calorieStore.entries.map(\.id))
        let pendingDraft = foodSelectionHandler == nil ? Self.loadPendingDraft(excluding: committedIDs) : nil
        // A saved review list restores its foods, but the meal and date come
        // from the screen that is opening the picker now.
        _selectedCategory = State(initialValue: category)
        _selectedEntryDate = State(initialValue: entryDate)
        _pendingEntries = State(initialValue: pendingDraft?.entries ?? [])
        _reviewingPendingEntries = State(initialValue: pendingDraft?.isReviewing ?? false)
        let stored = UserDefaults.standard.stringArray(forKey: Self.stableRecentSearchedFoodsKey)
            ?? UserDefaults.standard.stringArray(forKey: Self.recentSearchedFoodsKey)
            ?? []
        _recentSearchedFoodKeys = State(initialValue: stored.map { value in
            UUID(uuidString: value)?.uuidString.lowercased() ?? value
        })
    }

    var body: some View {
        NavigationView {
            ZStack {
                HyseBackdrop()
                VStack {
                    if foodSelectionHandler == nil {
                        VStack(spacing: HyseSpacing.small) {
                            HStack {
                                Picker("ui.category", selection: $selectedCategory) { ForEach(categoryStore.categories) { Text($0.localizedName).tag($0) } }.pickerStyle(.menu)
                                Spacer()
                                DatePicker("", selection: $selectedEntryDate, displayedComponents: .date)
                                    .labelsHidden()
                                    .accessibilityLabel(t("ui.date"))
                                    .onChange(of: selectedEntryDate) { oldValue, newValue in
                                        if Calendar.current.startOfDay(for: newValue) > Calendar.current.startOfDay(for: Date()), !premium.hasNutrition {
                                            selectedEntryDate = oldValue
                                            showingNutritionPremium = true
                                        }
                                    }
                            }
                        }
                        .padding(.horizontal, HyseSpacing.large)
                        .padding(.vertical, HyseSpacing.small)
                        .hyseGlassSurface(radius: HyseRadius.control)
                        .padding(.horizontal, HyseSpacing.page)
                        .padding(.top, HyseSpacing.small)
                    }

                    if selectedFood != nil || selectedRecipe != nil {
                        detail
                    } else if foodSelectionHandler == nil, reviewingPendingEntries {
                        pendingReview
                    } else {
                        if foodSelectionHandler == nil { entryActionStrip }
                        pickerList
                    }
                }

                if isLoadingBarcode {
                    Color.black.opacity(0.3).ignoresSafeArea()
                    HyseCard { ProgressView(t(barcodeStatusKey)).padding(HyseSpacing.small) }
                }
            }
            .navigationTitle(t(foodSelectionHandler == nil ? "ui.add_entry" : "daily_food.choose_food"))
            .task(id: "\(filter)|\(query)|\(frequencyStore.revision)|\(foodStore.globalFoods.count)") {
                await refreshFoodResults()
            }
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                if foodSelectionHandler == nil,
                   selectedFood == nil,
                   selectedRecipe == nil,
                   !pendingEntries.isEmpty {
                    pendingEntryActions
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t(foodSelectionHandler == nil ? "ui.back" : "app_tabs.cancel")) {
                        if foodSelectionHandler == nil, reviewingPendingEntries {
                            reviewingPendingEntries = false
                            persistPendingDraft()
                        } else if foodSelectionHandler == nil, (selectedFood != nil || selectedRecipe != nil) {
                            selectedFood = nil
                            selectedRecipe = nil
                        } else {
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if selectedFood != nil || selectedRecipe != nil {
                        Button(t("add_entry.add_to_list")) {
                            save()
                        }
                        .bold()
                        .disabled(nutrients == nil || isSaving)
                    }
                }
            }
            .sheet(isPresented: $showingRecipeEditor) { RecipeEditorView(foodStore: foodStore, recipeStore: recipeStore) }
            .sheet(isPresented: $showingRecipes) {
                NavigationStack {
                    RecipesView(foodStore: foodStore, recipeStore: recipeStore, frequencyStore: frequencyStore) { recipe, servings in
                        selectedFood = nil
                        selectedRecipe = recipe
                        recipeUnit = 0
                        recipeQuantity = formattedAmount(servings)
                        showingRecipes = false
                    }
                }
            }
            .sheet(isPresented: $showingQuickEntry) {
                QuickEntryView(calorieStore: calorieStore, categoryStore: categoryStore, userSettings: userSettings, initialCategory: selectedCategory, entryDate: selectedEntryDate)
            }
            .sheet(isPresented: $showingLocalFoodAnalysis) {
                LocalFoodAnalysisView(
                    foodStore: foodStore,
                    categoryStore: categoryStore,
                    calorieStore: calorieStore,
                    accountData: accountData,
                    frequencyStore: frequencyStore,
                    userSettings: userSettings,
                    availableCalories: availableCalories,
                    initialCategory: selectedCategory,
                    entryDate: selectedEntryDate,
                    onSaved: { dismiss() }
                )
            }
            .sheet(isPresented: $showingNutritionPremium) {
                PremiumPaywallView(requestedArea: .nutrition)
            }
            .sheet(item: $editingFood) { food in
                EditFoodView(foodStore: foodStore, foodItem: food) {
                    editingFood = nil
                    if selectedFood?.id == food.id { selectedFood = nil }
                }
            }
            .sheet(isPresented: $showingCreateFoodSheet) {
                CreateFoodView(foodStore: foodStore, barcode: scannedBarcodeForNewFood, draft: scannedExternalDraft, initialName: newFoodInitialName) { newFood in
                    selectFood(newFood)
                    scannedExternalDraft = nil
                    newFoodInitialName = ""
                }
            }
            .sheet(isPresented: $showingBarcodeScanner) {
                Group {
                    if scannerCreationReady {
                        CreateFoodView(foodStore: foodStore, barcode: scannedBarcodeForNewFood, draft: scannedExternalDraft) { newFood in
                            selectedFood = newFood
                            scannedExternalDraft = nil
                            scannerCreationReady = false
                            showingBarcodeScanner = false
                        }
                    } else {
                        NavigationView {
                            Group {
                                if isLoadingBarcode {
                                    VStack(spacing: HyseSpacing.medium) {
                                        ProgressView().controlSize(.large)
                                        Text(t(barcodeStatusKey)).font(.headline)
                                        Text(t("barcode.manual_explanation")).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                                    }
                                    .padding(HyseSpacing.xLarge)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .background(HyseColor.background)
                                    .navigationTitle("ui.create_food")
                                    .navigationBarTitleDisplayMode(.inline)
                                } else if scannerShowsManualEntry {
                            Form {
                                Section {
                                    TextField(t("barcode.manual_placeholder"), text: $manualBarcode)
                                        .keyboardType(.numberPad)
                                        .submitLabel(.search)
                                        .onSubmit { submitManualBarcodeFromScanner() }
                                } footer: {
                                    Text(t("barcode.manual_explanation"))
                                }
                            }
                            .navigationTitle(t("barcode.manual_title"))
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) {
                                    Button("ui.back") {
                                        manualBarcode = ""
                                        scannerShowsManualEntry = false
                                    }
                                }
                                ToolbarItem(placement: .confirmationAction) {
                                    Button(t("barcode.lookup")) { submitManualBarcodeFromScanner() }
                                        .disabled(manualBarcode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                }
                            }
                                } else {
                            BarcodeScannerView(
                                torchOn: $scannerTorchOn,
                                onScanned: { code in
                                    handleScannedBarcode(code)
                                },
                                onError: { err in
                                    showingBarcodeScanner = false
                                    alertMessage = err
                                }
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 22, style: .continuous)
                                    .stroke(.white, lineWidth: 3)
                                    .frame(width: 280, height: 170)
                                    .shadow(color: .black.opacity(0.55), radius: 5)
                                    .accessibilityHidden(true)
                            }
                            .safeAreaInset(edge: .bottom) {
                                HStack(spacing: 24) {
                                    Button { scannerTorchOn.toggle() } label: {
                                        Label(t("barcode.flashlight"), systemImage: scannerTorchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                                    }
                                    Button {
                                        scannerTorchOn = false
                                        scannerShowsManualEntry = true
                                    } label: {
                                        Label(t("barcode.enter_manually"), systemImage: "keyboard")
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(HyseColor.background)
                            }
                            .navigationTitle("ui.scan_barcode")
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) {
                                    Button("app_tabs.cancel") { showingBarcodeScanner = false }
                                }
                            }
                                }
                            }
                        }
                    }
                }
                .interactiveDismissDisabled(isLoadingBarcode)
            }
            .alert(t("barcode.camera_permission_title"), isPresented: $showingCameraExplanation) {
                Button(t("app_tabs.cancel"), role: .cancel) {}
                Button(t("barcode.allow_camera")) { requestCameraAccess() }
            } message: { Text(t("barcode.camera_permission_explanation")) }
            .alert(t("barcode.camera_permission_denied_title"), isPresented: $showingCameraDenied) {
                Button(t("app_tabs.cancel"), role: .cancel) {}
                Button(t("barcode.open_settings")) {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                Button(t("barcode.enter_manually")) { showingManualBarcode = true }
            } message: { Text(t("barcode.camera_permission_denied_message")) }
            .alert(t("barcode.manual_title"), isPresented: $showingManualBarcode) {
                TextField(t("barcode.manual_placeholder"), text: $manualBarcode)
                    .keyboardType(.numberPad)
                Button(t("app_tabs.cancel"), role: .cancel) { manualBarcode = "" }
                Button(t("barcode.lookup")) {
                    let code = manualBarcode
                    manualBarcode = ""
                    handleScannedBarcode(code)
                }
            } message: { Text(t("barcode.manual_explanation")) }
            .onChange(of: recipeUnit) { oldMode, newMode in
                guard oldMode != newMode, let recipe = selectedRecipe else { return }
                if newMode == 1 {
                    guard let portions = decimal(recipeQuantity) else { return }
                    let grams = portions * recipe.gramsPerServing
                    amount = formattedAmount(FoodUnit.gram.converted(grams, to: userSettings.defaultFoodUnit) ?? grams)
                } else {
                    guard let displayedAmount = decimal(amount), recipe.gramsPerServing > 0 else { return }
                    let grams = userSettings.defaultFoodUnit.converted(displayedAmount, to: .gram) ?? displayedAmount
                    recipeQuantity = formattedAmount(grams / recipe.gramsPerServing)
                }
            }
            .onChange(of: filter) { _, _ in selectedFood = nil; selectedRecipe = nil }
            .onChange(of: selectedEntryDate) { _, _ in persistPendingDraft() }
            .onChange(of: selectedCategory) { _, _ in persistPendingDraft() }
            .onChange(of: calorieStore.entries.map(\.id)) { _, _ in
                removeCommittedPendingEntries()
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase != .active else { return }
                removeCommittedPendingEntries()
                persistPendingDraft()
            }
            .onChange(of: foodStore.foods) { _, newFoods in
                if let current = selectedFood, let updated = newFoods.first(where: { $0.id == current.id }) {
                    selectedFood = updated
                }
                Task { await refreshFoodResults(loadRemote: false) }
            }
            .hyseAlert(isPresented: Binding(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } }), title: t("ui.notice"), message: alertMessage ?? "", buttonTitle: t("common.ok"))
            .confirmationDialog(t("food_tracking.goal_warning_title"), isPresented: $showingCalorieGoalWarning, titleVisibility: .visible) {
                Button(t("food_tracking.log_anyway")) { savePendingEntries(confirmedOverGoal: true) }
                Button(t("app_tabs.cancel"), role: .cancel) {}
            } message: { Text(t("food_tracking.goal_warning_amount", calorieGoalOverage)) }
        }
        .hyseScreen()
        .tint(.primary)
        .onAppear {
            removeCommittedPendingEntries()
            persistPendingDraft()
        }
    }

    private var pickerList: some View {
        List {
            HStack(spacing: HyseSpacing.medium) {
                Image(systemName: "magnifyingglass")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                TextField(t("add_entry.search_food"), text: $query)
                    .focused($searchFocused)
                    .submitLabel(.search)
                    .simultaneousGesture(TapGesture().onEnded { selectAllSearchText() })
                    .onChange(of: searchFocused) { _, isFocused in
                        if isFocused { selectAllSearchText() }
                    }
                HyseInfoButton(
                    title: t("add_entry.search_food"),
                    message: t("info.food_search.body")
                )
                Button { newFoodInitialName = ""; beginBarcodeScan() } label: {
                    Image(systemName: "barcode.viewfinder").frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(t("barcode.search_existing"))
            }
            .padding(.horizontal, HyseSpacing.medium)
            .padding(.vertical, HyseSpacing.small)
            .hyseGlassSurface(radius: HyseRadius.control)
            .overlay { RoundedRectangle(cornerRadius: HyseRadius.control, style: .continuous).stroke(searchFocused ? Color.primary.opacity(0.38) : HyseColor.border, lineWidth: searchFocused ? 2 : 1) }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: HyseSpacing.small, leading: HyseSpacing.page, bottom: HyseSpacing.small, trailing: HyseSpacing.page))

            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !recentSearchedFoods.isEmpty {
                VStack(alignment: .leading, spacing: HyseSpacing.small) {
                    HStack {
                        Label(t("add_entry.recently_searched"), systemImage: "clock.arrow.circlepath")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(t("add_entry.clear_search_history")) { clearSearchedFoods() }
                            .font(.caption)
                            .foregroundStyle(.primary)
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: HyseSpacing.small) {
                            ForEach(recentSearchedFoods) { food in
                                Button {
                                    rememberSearchedFood(food)
                                    selectFood(food)
                                } label: {
                                    HStack(spacing: HyseSpacing.xSmall) {
                                        Image(systemName: "fork.knife").font(.caption)
                                        Text(food.displayName(using: language)).font(.subheadline.weight(.medium)).lineLimit(1)
                                        if foodStore.isFavorite(food) {
                                            Image(systemName: "star.fill")
                                                .font(.caption2)
                                                .foregroundStyle(HyseColor.warning)
                                                .accessibilityLabel(t("ui.favourites"))
                                        }
                                    }
                                    .foregroundStyle(.primary)
                                    .padding(.horizontal, HyseSpacing.medium)
                                    .frame(height: 38)
                                    .background(HyseColor.surface, in: Capsule())
                                    .overlay(Capsule().stroke(HyseColor.border))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 0, leading: HyseSpacing.page, bottom: HyseSpacing.medium, trailing: HyseSpacing.page))
            }

            HStack(spacing: HyseSpacing.medium) {
                if foodSelectionHandler == nil {
                    Button {
                        searchFocused = false
                        showingRecipes = true
                    } label: {
                        searchSelector(title: t("recipes.recipes"), icon: "book.closed", chevron: "chevron.right")
                    }
                    .accessibilityLabel(t("add_entry.select_recipe"))
                }
                Menu {
                    Button(t("ui.recent")) { filter = 0 }
                    Button(t("ui.frequent")) { filter = 1 }
                    Button(t("ui.favourites")) { filter = 2 }
                    Button(t("ui.all")) { filter = 3 }
                } label: {
                    let keys = ["ui.recent", "ui.frequent", "ui.favourites", "ui.all"]
                    searchSelector(title: t(keys[min(max(filter, 0), 3)]), icon: "line.3.horizontal.decrease")
                }
            }
            .buttonStyle(.plain)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 0, leading: HyseSpacing.page, bottom: HyseSpacing.medium, trailing: HyseSpacing.page))
            if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Section {
                    HStack(spacing: HyseSpacing.medium) {
                        if isPreparingFoodResults || isSearchingRemoteFoods {
                            ProgressView().controlSize(.small)
                            Text(t(isPreparingFoodResults ? "add_entry.preparing_foods" : "add_entry.searching_foods"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                    // Keep this row in the list for the complete lifetime
                    // of a query. Otherwise the results jump upwards at the
                    // exact moment the remote search indicator disappears.
                    .frame(minHeight: 22)
                    .accessibilityElement(children: .combine)
                    .accessibilityHidden(!isPreparingFoodResults && !isSearchingRemoteFoods)
                }
            }
            if filter == 0 && query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !recentFoodGroups.isEmpty {
                ForEach(recentFoodGroups) { group in
                    Section(group.title) { ForEach(group.foods) { food in foodRow(food) } }
                }
            } else if isLoadingFrequentFoods {
                Section {
                    HStack(spacing: HyseSpacing.medium) {
                        ProgressView()
                            .controlSize(.small)
                        Text(t("add_entry.loading_frequent_foods"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .frame(minHeight: 44)
                    .accessibilityElement(children: .combine)
                }
            } else {
                if filteredFoods.isEmpty && !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isPreparingFoodResults && !isSearchingRemoteFoods {
                    Section {
                        HyseEmptyState(
                            icon: "fork.knife.circle",
                            title: t("add_entry.no_food_found"),
                            message: t("add_entry.create_food_from_search"),
                            actionTitle: t("ui.create_new_food"),
                            action: createFoodFromCurrentSearch
                        )
                    }
                } else {
                    Section { ForEach(filteredFoods) { food in foodRow(food) } }
                }
            }
        }
        .listStyle(.plain)
        .hyseForm()
    }

    private var entryActionStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: HyseSpacing.small) {
                entryActionLabel(t("add_entry.search"), icon: "magnifyingglass", selected: true)
                Button {
                    if premium.hasNutrition { showingLocalFoodAnalysis = true }
                    else { showingNutritionPremium = true }
                } label: {
                    entryActionLabel(
                        t("food_ai.short_title"),
                        icon: "text.magnifyingglass",
                        premiumArea: premium.hasNutrition ? nil : .nutrition
                    )
                }
                .buttonStyle(.plain)
                Button { newFoodInitialName = ""; beginBarcodeScan() } label: {
                    entryActionLabel(t("ui.scan_barcode"), icon: "barcode.viewfinder")
                }
                .buttonStyle(.plain)
                Button { showingQuickEntry = true } label: {
                    entryActionLabel(t("app_tabs.quick_entry"), icon: "bolt.fill")
                }
                .buttonStyle(.plain)
                createEntryMenu
            }
        }
        .padding(.horizontal, HyseSpacing.page)
        .padding(.bottom, HyseSpacing.small)
        .background(HyseColor.background)
    }

    private var pendingReview: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: HyseSpacing.xSmall) {
                    Text(t("batch_add.preview_title"))
                        .font(.headline)
                    Text(t("batch_add.preview_hint"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    HStack {
                        Text(t("batch_add.preview_total"))
                        Spacer()
                        Text("\(calorieText(pendingEntries.reduce(0) { $0 + $1.entry.kcal })) kcal")
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                    }
                    .padding(.top, HyseSpacing.xSmall)
                }
                .padding(.vertical, HyseSpacing.small)
            }
            .listRowBackground(Color.clear)

            Section(t("batch_add.selected_foods")) {
                ForEach(pendingEntries) { pending in
                    pendingReviewRow(pending)
                }
            }
        }
        .listStyle(.plain)
        .hyseForm()
    }

    private var pendingEntryActions: some View {
        HStack(spacing: HyseSpacing.medium) {
            if !reviewingPendingEntries {
                Button {
                    beginPendingReview()
                } label: {
                    Text(t("batch_add.review_count", pendingEntries.count))
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(HyseColor.surface, in: RoundedRectangle(cornerRadius: HyseRadius.control))
                }
                .buttonStyle(.plain)
                .disabled(isSaving)
            }

            Button {
                savePendingEntries()
            } label: {
                Text(t("ui.log_food"))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(HyseColor.accent, in: RoundedRectangle(cornerRadius: HyseRadius.control))
            }
            .buttonStyle(.plain)
            .disabled(isSaving)
        }
        .padding(.horizontal, HyseSpacing.page)
        .padding(.top, HyseSpacing.small)
        .padding(.bottom, HyseSpacing.small)
        .background(HyseColor.background)
    }

    private func pendingReviewRow(_ pending: PendingFoodEntry) -> some View {
        HStack(spacing: HyseSpacing.small) {
            VStack(alignment: .leading, spacing: HyseSpacing.xSmall) {
                Text(pending.entry.name)
                    .font(.body.weight(.medium))
                    .lineLimit(2)
                Text("\(calorieText(pending.entry.kcal)) kcal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: HyseSpacing.small)
            TextField("0", text: pendingAmountBinding(for: pending.id))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 72)
                .textFieldStyle(.plain)
                .background(Color.clear)
                .accessibilityLabel(t("recipe_editor.amount"))
            Text(pendingAmountUnit(for: pending))
                .foregroundStyle(.secondary)
                .frame(minWidth: 34, alignment: .leading)
            Button(role: .destructive) {
                removePendingEntry(pending.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(t("settings.delete"))
        }
        .padding(.vertical, HyseSpacing.xSmall)
    }

    private func pendingAmountBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: { pendingEntries.first(where: { $0.id == id })?.amountText ?? "" },
            set: { newValue in
                guard let index = pendingEntries.firstIndex(where: { $0.id == id }) else { return }
                pendingEntries[index].amountText = newValue
                _ = applyPendingAmount(at: index)
                persistPendingDraft()
            }
        )
    }

    private func pendingAmountUnit(for pending: PendingFoodEntry) -> String {
        if pending.usesPortion {
            return pending.entry.portionName ?? t("ui.serving")
        }
        let unit = pending.food.map(preferredDisplayUnit(for:)) ?? userSettings.defaultFoodUnit
        return unit.rawValue
    }

    private func beginPendingReview() {
        guard !pendingEntries.isEmpty else { return }
        searchFocused = false
        reviewingPendingEntries = true
        persistPendingDraft()
    }

    private func removePendingEntry(_ id: UUID) {
        pendingEntries.removeAll { $0.id == id }
        if pendingEntries.isEmpty {
            reviewingPendingEntries = false
        }
        persistPendingDraft()
    }

    private func removeCommittedPendingEntries() {
        let committedIDs = Set(calorieStore.entries.map(\.id))
        guard pendingEntries.contains(where: { committedIDs.contains($0.id) }) else { return }
        pendingEntries.removeAll { committedIDs.contains($0.id) }
        if pendingEntries.isEmpty { reviewingPendingEntries = false }
        persistPendingDraft()
    }

    private var createEntryMenu: some View {
        Menu {
            Button {
                newFoodInitialName = ""
                beginBarcodeScan()
            } label: {
                Label(t("app_tabs.food_barcode"), systemImage: "barcode.viewfinder")
            }
            Button {
                scannedBarcodeForNewFood = ""
                scannedExternalDraft = nil
                newFoodInitialName = ""
                Task { @MainActor in
                    await Task.yield()
                    showingCreateFoodSheet = true
                }
            } label: {
                Label(t("app_tabs.food_without_barcode"), systemImage: "fork.knife.circle")
            }
            Button {
                showingRecipeEditor = true
            } label: {
                Label(t("add_entry.create_recipe"), systemImage: "doc.badge.plus")
            }
        } label: {
            entryActionLabel(t("add_entry.create_action"), icon: "plus")
        }
    }

    private func entryActionLabel(
        _ title: String,
        icon: String,
        selected: Bool = false,
        premiumArea: PremiumArea? = nil
    ) -> some View {
        VStack(spacing: HyseSpacing.xSmall) {
            Image(systemName: icon)
                .font(.headline)
                .frame(height: 22)
                .overlay(alignment: .topTrailing) {
                    if let premiumArea {
                        PremiumFeatureIcon(area: premiumArea)
                            .offset(x: 11, y: -8)
                    }
                }
            Text(title)
                .font(.caption2.weight(selected ? .bold : .medium))
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(Color.primary)
        .frame(width: 94, height: 68)
        .background(selected ? Color.primary.opacity(0.10) : HyseColor.surface, in: RoundedRectangle(cornerRadius: HyseRadius.control, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: HyseRadius.control, style: .continuous).stroke(selected ? Color.primary.opacity(0.28) : HyseColor.border) }
    }

    private func searchSelector(title: String, icon: String, chevron: String = "chevron.down") -> some View {
        HStack(spacing: HyseSpacing.small) {
            Image(systemName: icon).foregroundStyle(.secondary)
            Text(title).font(.subheadline.weight(.semibold)).lineLimit(1)
            Spacer(minLength: 0)
            Image(systemName: chevron).font(.caption).foregroundStyle(.secondary)
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, HyseSpacing.medium)
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(HyseColor.surface, in: RoundedRectangle(cornerRadius: HyseRadius.control, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: HyseRadius.control, style: .continuous).stroke(HyseColor.border) }
    }

    private func selectFood(_ food: FoodItem) {
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { rememberSearchedFood(food) }
        searchFocused = false
        if let foodSelectionHandler {
            foodSelectionHandler(food)
            if dismissAfterFoodSelection { dismiss() }
            return
        }
        selectedFood = food
        refreshMicronutrients(for: food)
        // Use the same alias-aware record that is displayed below the search
        // result, so the row and the opened amount editor can never disagree.
        let suggestion = recentUsage(for: food) ?? accountData.suggestion(for: food)
        let hasRecordedUsage = suggestion.usedAt != .distantPast && suggestion.amount > 0
        if let recentID = suggestion.portionID,
           let recentPortion = food.portions.first(where: { $0.id == recentID }),
           let recentCount = suggestion.portionCount,
           recentCount > 0,
           recentPortion.baseAmount(in: food.unit) != nil {
            selectedPortionID = recentID
            amount = formattedAmount(recentCount)
            foodAmountMode = 1
        } else if hasRecordedUsage {
            // A previous free amount (for example 45 g) must remain a free
            // amount. Do not replace it with the food's default 1 × portion.
            selectedPortionID = nil
            let displayUnit = preferredDisplayUnit(for: food)
            amount = formattedAmount(suggestion.unit.converted(suggestion.amount, to: displayUnit) ?? suggestion.amount)
            foodAmountMode = 0
        } else if let defaultPortion = food.defaultPortion {
            selectedPortionID = defaultPortion.id
            amount = "1"
            foodAmountMode = 1
        } else {
            selectedPortionID = nil
            let displayUnit = preferredDisplayUnit(for: food)
            amount = formattedAmount(suggestion.unit.converted(suggestion.amount, to: displayUnit) ?? suggestion.amount)
            foodAmountMode = 0
        }
    }

    private func refreshMicronutrients(for food: FoodItem) {
        guard premium.hasNutrition,
              let barcode = BarcodeNormalizer.normalizedIfValid(food.barcode) else { return }
        let scope = foodStore.micronutrientScopeID
        Task {
            guard let imported = try? await OpenFoodFactsService.shared.fetchProduct(barcode: barcode)?.micronutrients,
                  !imported.isEmpty,
                  premium.hasNutrition,
                  foodStore.micronutrientScopeID == scope,
                  calorieStore.micronutrientScopeID == scope else { return }
            foodStore.applyOpenFoodFactsMicronutrients(imported, barcode: barcode)
            let current = foodStore.food(id: food.id) ?? food
            let converted = imported.converted(from: .gram, to: current.unit)
            var refreshed = current
            refreshed.micronutrients = current.micronutrients?.addingOpenFoodFacts(converted) ?? converted
            if selectedFood?.id == food.id { selectedFood = refreshed }
            calorieStore.applyOpenFoodFactsMicronutrients(
                imported, barcode: barcode, foods: foodStore.availableFoods + [refreshed]
            )
        }
    }

    private func selectAllSearchText() {
        guard !query.isEmpty else { return }
        DispatchQueue.main.async {
            UIApplication.shared.sendAction(#selector(UIResponder.selectAll(_:)), to: nil, from: nil, for: nil)
        }
    }

    private func selectAmountText() {
        guard !amount.isEmpty else { return }
        DispatchQueue.main.async {
            UIApplication.shared.sendAction(#selector(UIResponder.selectAll(_:)), to: nil, from: nil, for: nil)
        }
    }

    private func quickAddFood(_ food: FoodItem) {
        if foodSelectionHandler != nil {
            selectFood(food)
            return
        }
        // Keep the detail editor out of the render cycle for the row's plus
        // action. The selection is only needed to reuse the existing amount
        // and entry-building logic, not to present an intermediate screen.
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            selectFood(food)
            save()
        }
    }

    private var recentSearchedFoods: [FoodItem] {
        let foodsByKey = FoodHistoryIdentity.foodMap(foodStore.availableFoods)
        return recentSearchedFoodKeys.compactMap { foodsByKey[$0] }.prefix(8).map { $0 }
    }

    private func rememberSearchedFood(_ food: FoodItem) {
        let key = FoodHistoryIdentity.key(for: food)
        recentSearchedFoodKeys.removeAll { $0 == key }
        recentSearchedFoodKeys.insert(key, at: 0)
        if recentSearchedFoodKeys.count > 12 { recentSearchedFoodKeys.removeLast(recentSearchedFoodKeys.count - 12) }
        UserDefaults.standard.set(recentSearchedFoodKeys, forKey: Self.stableRecentSearchedFoodsKey)
    }

    private func clearSearchedFoods() {
        recentSearchedFoodKeys = []
        UserDefaults.standard.removeObject(forKey: Self.recentSearchedFoodsKey)
        UserDefaults.standard.removeObject(forKey: Self.stableRecentSearchedFoodsKey)
    }

    private func createFoodFromCurrentSearch() {
        newFoodInitialName = query.trimmingCharacters(in: .whitespacesAndNewlines)
        scannedBarcodeForNewFood = ""
        scannedExternalDraft = nil
        showingCreateFoodSheet = true
    }

    private func beginBarcodeScan() {
        scannerTorchOn = false
        scannerShowsManualEntry = false
        scannerCreationReady = false
        isLoadingBarcode = false
        manualBarcode = ""
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            showingBarcodeScanner = true
        case .notDetermined:
            showingCameraExplanation = true
        case .denied, .restricted:
            showingCameraDenied = true
        @unknown default:
            showingCameraDenied = true
        }
    }

    private func submitManualBarcodeFromScanner() {
        let code = manualBarcode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return }
        manualBarcode = ""
        scannerShowsManualEntry = false
        handleScannedBarcode(code)
    }

    private func requestCameraAccess() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                if granted { showingBarcodeScanner = true }
                else { showingCameraDenied = true }
            }
        }
    }

    private func handleScannedBarcode(_ code: String) {
        let normalized: String
        do { normalized = try BarcodeNormalizer.normalize(code) }
        catch { alertMessage = error.localizedDescription; return }

        barcodeStatusKey = "barcode.checking_hyse"
        isLoadingBarcode = true
        Task {
            let cachedMatches = foodStore.barcodeMatches(normalized)
            if cachedMatches.count == 1, let knownFood = cachedMatches.first {
                isLoadingBarcode = false
                showingBarcodeScanner = false
                selectFood(knownFood)
                return
            }
            if cachedMatches.count > 1 {
                isLoadingBarcode = false
                showingBarcodeScanner = false
                alertMessage = t("barcode.conflicting_matches")
                return
            }

            // Start the external fallback while the two indexed Hyse lookups
            // run. Hyse still wins whenever it has a result, but an unknown
            // barcode no longer pays both network latencies sequentially.
            let externalTask = Task { try? await OpenFoodFactsService.shared.fetchProduct(barcode: normalized) }
            let matches = await foodStore.lookupKnownBarcode(normalized)
            if matches.count == 1, let knownFood = matches.first {
                externalTask.cancel()
                isLoadingBarcode = false
                showingBarcodeScanner = false
                selectFood(knownFood)
                return
            }
            if matches.count > 1 {
                externalTask.cancel()
                isLoadingBarcode = false
                showingBarcodeScanner = false
                alertMessage = t("barcode.conflicting_matches")
                return
            }
            barcodeStatusKey = "barcode.searching_external"
            let fetched = await externalTask.value
            isLoadingBarcode = false
            scannedExternalDraft = fetched
            scannedBarcodeForNewFood = normalized
            if showingBarcodeScanner {
                scannerCreationReady = true
            } else {
                showingCreateFoodSheet = true
            }
        }
    }

    private var filteredFoods: [FoodItem] { visibleFoods }

    private var isLoadingFrequentFoods: Bool {
        filter == 1
            && query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && filteredFoods.isEmpty
            && (isPreparingFoodResults || frequencyStore.isHydrating)
    }

    @MainActor
    private func refreshFoodResults(loadRemote: Bool = true) async {
        let requestedQuery = query
        let requestedFilter = filter
        isPreparingFoodResults = true
        if requestedQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            var historyKeys = recentSearchedFoodKeys
            if requestedFilter == 0 {
                historyKeys += accountData.recentUsage.compactMap { $0.globalFoodRecordID.map { "global:\($0)" } }
                historyKeys += calorieStore.entries.compactMap { $0.globalFoodRecordID.map { "global:\($0)" } }
                historyKeys += frequencyStore.recentSourceKeys
            } else if requestedFilter == 1 {
                historyKeys += Array(frequencyStore.sourceTotalCounts.keys)
                historyKeys += frequencyStore.recentSourceKeys
            }
            let globalIDs = FoodHistoryIdentity.globalRecordIDs(from: historyKeys)
            await foodStore.hydrateGlobalFoods(recordIDs: globalIDs)
            guard !Task.isCancelled, query == requestedQuery, filter == requestedFilter else { return }
        }
        let localSnapshot = foodStore.availableFoods
        let counts = frequencyStore.totalCounts
        let recentIDs = frequencyStore.recentItemIDs
        let sourceCounts = frequencyStore.sourceTotalCounts
        let recentSources = frequencyStore.recentSourceKeys
        let localResults = await Task.detached(priority: .userInitiated) {
            Self.makeVisibleFoods(
                from: localSnapshot,
                query: requestedQuery,
                filter: requestedFilter,
                usageCounts: counts,
                recentIDs: recentIDs,
                sourceUsageCounts: sourceCounts,
                recentSourceKeys: recentSources
            )
        }.value
        guard !Task.isCancelled, query == requestedQuery, filter == requestedFilter else { return }
        visibleFoods = localResults
        isPreparingFoodResults = false

        let trimmed = requestedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard loadRemote, trimmed.count >= 2 else {
            isSearchingRemoteFoods = false
            return
        }

        isSearchingRemoteFoods = true
        await foodStore.hydrateGlobalSearch(for: requestedQuery)
        guard !Task.isCancelled, query == requestedQuery, filter == requestedFilter else { return }
        let refreshedSnapshot = foodStore.availableFoods
        let refreshedResults = await Task.detached(priority: .userInitiated) {
            Self.makeVisibleFoods(
                from: refreshedSnapshot,
                query: requestedQuery,
                filter: requestedFilter,
                usageCounts: counts,
                recentIDs: recentIDs,
                sourceUsageCounts: sourceCounts,
                recentSourceKeys: recentSources
            )
        }.value
        guard !Task.isCancelled, query == requestedQuery, filter == requestedFilter else { return }
        visibleFoods = refreshedResults
        isSearchingRemoteFoods = false
    }

    nonisolated private static func makeVisibleFoods(
        from foods: [FoodItem],
        query: String,
        filter: Int,
        usageCounts: [UUID: Int],
        recentIDs: [UUID],
        sourceUsageCounts: [String: Int],
        recentSourceKeys: [String]
    ) -> [FoodItem] {
        func usageCount(_ food: FoodItem) -> Int {
            max(usageCounts[food.id, default: 0], sourceUsageCounts[FrequencyStore.sourceKey(for: food), default: 0])
        }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return Array(foods.lazy.filter { food in
                FoodSearchRanker.matches(food, query: trimmed)
                    && (filter != 2 || food.isFavorite)
            }
            .sorted {
                // Keep the relevance group ahead of history while preserving
                // the selected frequency ordering among similarly good hits.
                let leftScore = FoodSearchRanker.relevanceScore($0, query: trimmed)
                let rightScore = FoodSearchRanker.relevanceScore($1, query: trimmed)
                if leftScore != rightScore { return leftScore < rightScore }
                if filter == 1 {
                    let leftCount = usageCount($0)
                    let rightCount = usageCount($1)
                    if leftCount != rightCount { return leftCount > rightCount }
                }
                if filter != 2, $0.isFavorite != $1.isFavorite { return $0.isFavorite }
                if FoodSearchRanker.orderedBefore($0, $1, query: trimmed) { return true }
                if FoodSearchRanker.orderedBefore($1, $0, query: trimmed) { return false }
                return $0.id.uuidString < $1.id.uuidString
            }
            .prefix(120))
        }

        switch filter {
        case 0:
            return [] // Dated recent groups are rendered separately.
        case 1:
            let ranks = recentIDs.enumerated().reduce(into: [UUID: Int]()) { result, value in
                if result[value.element] == nil { result[value.element] = value.offset }
            }
            let sourceRanks = recentSourceKeys.enumerated().reduce(into: [String: Int]()) { result, value in
                if result[value.element] == nil { result[value.element] = value.offset }
            }
            func rank(_ food: FoodItem) -> Int {
                min(ranks[food.id, default: .max], sourceRanks[FrequencyStore.sourceKey(for: food), default: .max])
            }
            return Array(foods.lazy.filter {
                usageCount($0) > 0 || rank($0) != .max
            }.sorted {
                let leftCount = usageCount($0)
                let rightCount = usageCount($1)
                if leftCount != rightCount { return leftCount > rightCount }
                let leftRank = rank($0)
                let rightRank = rank($1)
                if leftRank != rightRank { return leftRank < rightRank }
                if $0.isFavorite != $1.isFavorite { return $0.isFavorite }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            })
        case 2:
            return Array(foods.lazy.filter(\.isFavorite).prefix(120))
        default:
            return Array(foods.sorted {
                if $0.isFavorite != $1.isFavorite { return $0.isFavorite }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }.prefix(120))
        }
    }

    private struct RecentFoodGroup: Identifiable {
        let day: Date
        let title: String
        let foods: [FoodItem]
        var id: Date { day }
    }

    private var recentFoodGroups: [RecentFoodGroup] {
        let calendar = Calendar.autoupdatingCurrent
        let foodsByKey = foodStore.availableFoods.reduce(into: [String: FoodItem]()) { result, food in
            result[AccountDataStore.foodKey(food)] = food
            result["local:\(food.id.uuidString.lowercased())"] = food
            if let global = food.globalRecordID, !global.isEmpty { result["global:\(global)"] = food }
        }
        var latestByFoodID: [UUID: (Date, FoodItem)] = [:]
        func include(_ food: FoodItem, usedAt: Date) {
            guard usedAt != .distantPast else { return }
            if let previous = latestByFoodID[food.id], previous.0 >= usedAt { return }
            latestByFoodID[food.id] = (usedAt, food)
        }
        for usage in accountData.recentUsage {
            if let food = foodsByKey[usage.foodKey] { include(food, usedAt: usage.usedAt) }
        }
        // A server refresh can temporarily replace the usage aggregate with an
        // older snapshot. The saved diary entry still proves this food was used.
        for entry in calorieStore.entries where entry.recipeId == nil {
            let food = entry.globalFoodRecordID.flatMap { foodsByKey["global:\($0)"] }
                ?? entry.foodItemId.flatMap { foodsByKey["local:\($0.uuidString.lowercased())"] }
            if let food { include(food, usedAt: entry.date) }
        }
        let values = latestByFoodID.values.sorted { $0.0 > $1.0 }
            .map { (calendar.startOfDay(for: $0.0), $0.1) }
        let grouped = Dictionary(grouping: values, by: \.0)
        return grouped.keys.sorted(by: >).map { day in
            let title: String
            if calendar.isDateInToday(day) { title = t("content.today") }
            else if calendar.isDateInYesterday(day) { title = t("recent.yesterday") }
            else if let weekAgo = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: Date())), day >= weekAgo {
                title = day.formatted(.dateTime.weekday(.wide).locale(language.locale))
            } else {
                title = day.formatted(.dateTime.weekday(.wide).day().month().year().locale(language.locale))
            }
            var seen = Set<UUID>()
            let foods = (grouped[day] ?? []).compactMap { seen.insert($0.1.id).inserted ? $0.1 : nil }
            return RecentFoodGroup(day: day, title: title, foods: foods)
        }
    }

    private func foodRow(_ food: FoodItem) -> some View {
        HStack(spacing: HyseSpacing.medium) {
            Button { selectFood(food) } label: {
                VStack(alignment: .leading, spacing: HyseSpacing.xSmall) {
                    HStack(spacing: HyseSpacing.small) {
                        Text(food.displayName(using: language))
                            .font(.body.weight(.medium))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        if foodStore.isFavorite(food) {
                            Image(systemName: "star.fill")
                                .font(.caption)
                                .foregroundStyle(HyseColor.warning)
                                .accessibilityLabel(t("ui.favourites"))
                        }
                        if foodStore.isGlobalFood(food.id) {
                            Image(systemName: "globe.europe.africa.fill")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let recent = recentUsage(for: food), recent.usedAt != .distantPast {
                        Text(t("recent.last_details", recentAmount(recent, food: food), localizedMealName(recent.mealKey), recent.usedAt.formatted(.dateTime.hour().minute().locale(language.locale))))
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text([food.brand, referenceAmount(for: food)].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Text("\(Int(food.kcalPerNutritionReference)) kcal")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Button { quickAddFood(food) } label: {
                Image(systemName: "plus")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 34, height: 34)
                    .overlay(Circle().stroke(Color.secondary, lineWidth: 1.5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(t(foodSelectionHandler == nil ? "ui.log_food" : "daily_food.choose_food"))
        }
        .padding(.vertical, HyseSpacing.xSmall)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button { toggleFoodFavoriteOnce(food) } label: {
                Label(t(foodStore.isFavorite(food) ? "add_entry.remove_from_favorites" : "add_entry.add_favorites"), systemImage: foodStore.isFavorite(food) ? "star.slash" : "star")
            }
            .tint(HyseColor.warning)
            if !foodStore.isGlobalFood(food.id) {
                Button { editingFood = food } label: { Label(t("ui.edit_food"), systemImage: "pencil") }
                    .tint(.secondary)
            }
        }
    }

    private func recentUsage(for food: FoodItem) -> LastUsedAmount? {
        var keys = [AccountDataStore.foodKey(food), "local:\(food.id.uuidString.lowercased())"]
        if let global = food.globalRecordID, !global.isEmpty { keys.append("global:\(global)") }
        return keys.compactMap { accountData.lastUsedAmounts[$0] }.max { $0.usedAt < $1.usedAt }
    }

    private func recentAmount(_ recent: LastUsedAmount, food: FoodItem) -> String {
        if let portionID = recent.portionID,
           let portionCount = recent.portionCount,
           let portion = food.portions.first(where: { $0.id == portionID }) {
            return "\(portionCount.clean) × \(portion.displayName(using: language))"
        }
        let displayUnit = preferredDisplayUnit(for: food)
        let displayedAmount = recent.unit.converted(recent.amount, to: displayUnit) ?? recent.amount
        return "\(formattedAmount(displayedAmount)) \(displayUnit.rawValue)"
    }

    private func toggleFoodFavoriteOnce(_ food: FoodItem) {
        guard favoriteActionsInFlight.insert(food.id).inserted else { return }
        foodStore.toggleFavorite(food)
        Task { await refreshFoodResults(loadRemote: false) }
        releaseFavoriteAction(food.id)
    }

    private func releaseFavoriteAction(_ id: UUID) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            favoriteActionsInFlight.remove(id)
        }
    }
    private func localizedMealName(_ key: String) -> String {
        guard let systemKey = MealCategory.legacySystemKey(for: key) else { return key }
        return t("meal.\(systemKey)")
    }
    private func recentRank(_ id: UUID) -> Int { frequencyStore.recentItemIDs.firstIndex(of: id) ?? Int.max }

    private var detail: some View { Form {
        Section("recipe_editor.amount") {
            if let recipe = selectedRecipe {
                Text(recipe.name).bold()
                Picker("ui.unit", selection: $recipeUnit) { Text("ui.serving").tag(0); Text(userSettings.defaultFoodUnit.rawValue).tag(1) }.pickerStyle(.segmented)
                if recipeUnit == 0 {
                    LabeledContent("recipe_editor.servings") { TextField(t("common.quantity"), text: $recipeQuantity).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80) }
                    amountStepper
                } else {
                    LabeledContent("recipe_editor.amount") { HStack { TextField(userSettings.defaultFoodUnit.rawValue, text: $amount).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80); Text(userSettings.defaultFoodUnit.rawValue) } }
                    amountStepper
                }
            } else if let food = selectedFood {
                HStack {
                    Text(food.displayName(using: language)).bold()
                    Spacer()
                    Button { toggleFoodFavoriteOnce(food) } label: {
                        Image(systemName: foodStore.isFavorite(food) ? "star.fill" : "star")
                            .foregroundStyle(foodStore.isFavorite(food) ? HyseColor.warning : .secondary)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .disabled(favoriteActionsInFlight.contains(food.id))
                    .accessibilityLabel(foodStore.isFavorite(food) ? t("add_entry.remove_from_favorites") : t("add_entry.add_favorites"))
                    Button {
                        editingFood = food
                    } label: {
                        Label("ui.edit_food", systemImage: "pencil")
                            .font(.subheadline)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(t("ui.edit_food"))
                }
                if let provider = food.externalSource, !provider.isEmpty {
                    Label(t("barcode.source_attribution", provider), systemImage: "info.circle")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("barcode.external_quality_notice").font(.caption).foregroundStyle(.secondary)
                }
                if !food.portions.isEmpty, let portion = selectedPortion {
                    Picker("ui.unit", selection: foodAmountModeSelection) {
                        Text(preferredDisplayUnit(for: food).rawValue).tag(0)
                        Text("ui.serving").tag(1)
                    }.pickerStyle(.segmented)

                    if foodAmountMode == 1 {
                        Picker(portion.displayName(using: language), selection: $selectedPortionID) {
                            ForEach(food.sortedPortions) { value in
                                Text(portionPickerLabel(value, food: food)).tag(Optional(value.id))
                            }
                        }
                        portionWheel
                    }

                    if foodAmountMode == 1 {
                        LabeledContent("recipe_editor.servings") {
                            Text(formattedAmount(decimal(amount) ?? 0))
                                .font(.body.weight(.semibold).monospacedDigit())
                                .foregroundStyle(.primary)
                                .contentTransition(.numericText(value: decimal(amount) ?? 0))
                        }
                        if let baseAmount = selectedPortionBaseAmount {
                            let displayUnit = preferredDisplayUnit(for: food)
                            let displayedAmount = food.unit.converted(baseAmount, to: displayUnit) ?? baseAmount
                            Text(t("food_portion.one_equals", portion.displayName(using: language), formattedAmount(displayedAmount), displayUnit.rawValue))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        amountStepper
                    } else {
                        LabeledContent("recipe_editor.amount") { HStack { foodAmountTextField(for: food); Text(preferredDisplayUnit(for: food).rawValue) } }
                        amountStepper
                    }
                } else {
                    LabeledContent("recipe_editor.amount") { HStack { foodAmountTextField(for: food); Text(preferredDisplayUnit(for: food).rawValue) } }
                    amountStepper
                }
            }
        }
        if entryGrams == nil {
            Section { Text(t("add_entry.amount_limit")).foregroundStyle(HyseColor.danger) }
        }
        if let n = nutrients { Section { NutrientOverview(nutrients: n, amountLabel: visibleAmountLabel) } }
        if let food = selectedFood {
            Section {
                MicronutrientEditorButton(food: food, amount: entryGrams ?? 100, profile: Binding(
                    get: { foodStore.food(id: food.id)?.micronutrients ?? selectedFood?.micronutrients },
                    set: { profile in
                        guard let currentSelection = selectedFood else { return }
                        var updated = foodStore.food(id: currentSelection.id) ?? currentSelection
                        updated.micronutrients = profile
                        selectedFood = updated
                        foodStore.updateFood(updated)
                    }
                ))
            }
        } else if let food = recipeFood {
            Section {
                MicronutrientReadOnlyButton(profile: food.micronutrients, amount: entryGrams ?? 100, unit: .gram)
            }
        }
    }.hyseForm() }

    private func foodAmountTextField(for food: FoodItem) -> some View {
        TextField(preferredDisplayUnit(for: food).rawValue, text: $amount)
            .keyboardType(.decimalPad)
            .focused($amountFocused)
            .multilineTextAlignment(.trailing)
            .frame(width: 80)
            .simultaneousGesture(TapGesture().onEnded { selectAmountText() })
            .onChange(of: amountFocused) { _, isFocused in
                if isFocused { selectAmountText() }
            }
    }

    private func decimal(_ text: String) -> Double? {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: "¼", with: "1/4")
            .replacingOccurrences(of: "½", with: "1/2")
            .replacingOccurrences(of: "¾", with: "3/4")
            .replacingOccurrences(of: "⅓", with: "1/3")
            .replacingOccurrences(of: "⅔", with: "2/3")
        if let slash = normalized.firstIndex(of: "/") {
            let numerator = Double(normalized[..<slash])
            let denominator = Double(normalized[normalized.index(after: slash)...])
            guard let numerator, let denominator, denominator != 0 else { return nil }
            let value = numerator / denominator
            return value.isFinite ? value : nil
        }
        guard let value = Double(normalized), value.isFinite else { return nil }
        return value
    }
    private func formattedAmount(_ value: Double) -> String {
        guard value.isFinite else { return "0" }
        if value.rounded() == value, let integer = Int(exactly: value) { return String(integer) }
        return String(format: "%.2f", locale: language.locale, value)
    }
    private func calorieText(_ value: Double) -> String {
        guard value.isFinite, let rounded = Int(exactly: value.rounded()) else { return "–" }
        return String(rounded)
    }

    private var amountStepperBinding: Binding<Double> {
        Binding(
            get: {
                if selectedRecipe != nil && recipeUnit == 0 {
                    return min(max(decimal(recipeQuantity) ?? 0, 0), 10_000)
                }
                return min(max(decimal(amount) ?? 0, 0), 10_000)
            },
            set: { value in
                let text = formattedAmount(max(value, 0))
                if selectedRecipe != nil && recipeUnit == 0 {
                    recipeQuantity = text
                } else {
                    amount = text
                }
            }
        )
    }

    private var amountStepperStep: Double {
        if selectedRecipe != nil && recipeUnit == 0 { return 0.25 }
        if selectedFood != nil && foodAmountMode == 1 { return 1 }
        return 5
    }

    private var amountStepperUnit: String {
        if selectedRecipe != nil && recipeUnit == 0 { return t("ui.serving") }
        if let food = selectedFood {
            return foodAmountMode == 1 ? t("ui.serving") : preferredDisplayUnit(for: food).rawValue
        }
        return userSettings.defaultFoodUnit.rawValue
    }

    private var amountStepper: some View {
        Stepper(value: amountStepperBinding, in: 0...10_000, step: amountStepperStep) {
            HStack(spacing: HyseSpacing.small) {
                Label(t("ui.quick_selection"), systemImage: "plusminus")
                Spacer(minLength: 0)
                Text("± \(formattedAmount(amountStepperStep)) \(amountStepperUnit)")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var portionWheel: some View {
        VStack(spacing: 4) {
            HStack {
                Text("ui.quick_selection")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(t("food_portion.total", formattedAmount(decimal(amount) ?? 0)))
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                HyseInfoButton(
                    title: t("info.portions.title"),
                    message: t("info.portions.body")
                )
            }

            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    Text("food_portion.whole")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Picker(t("food_portion.whole"), selection: wholePortionSelection) {
                        ForEach(0...50, id: \.self) { value in
                            Text("\(value)").font(.body.monospacedDigit()).tag(value)
                        }
                    }
                    .pickerStyle(.wheel)
                    .labelsHidden()
                }

                Divider().frame(height: 82)

                VStack(spacing: 0) {
                    Text("food_portion.fraction")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Picker(t("food_portion.fraction"), selection: portionFractionSelection) {
                        ForEach(PortionFraction.allCases) { fraction in
                            Text(fraction.label).font(.body.weight(.medium)).tag(fraction)
                        }
                    }
                    .pickerStyle(.wheel)
                    .labelsHidden()
                }
            }
            .frame(height: 112)
            .clipped()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .hyseGlassSurface(radius: HyseRadius.control)
    }

    private var wholePortionSelection: Binding<Int> {
        Binding(
            get: { Int(floor(min(max(decimal(amount) ?? 0, 0), 50))) },
            set: { whole in setPortionWheelAmount(whole: whole, fraction: selectedPortionFraction) }
        )
    }

    private var portionFractionSelection: Binding<PortionFraction> {
        Binding(
            get: { selectedPortionFraction },
            set: { fraction in setPortionWheelAmount(whole: wholePortionSelection.wrappedValue, fraction: fraction) }
        )
    }

    private var selectedPortionFraction: PortionFraction {
        let value = max(decimal(amount) ?? 0, 0)
        let remainder = value - floor(value)
        return PortionFraction.allCases.min { abs($0.value - remainder) < abs($1.value - remainder) } ?? .none
    }

    private func setPortionWheelAmount(whole: Int, fraction: PortionFraction) {
        let value = Double(whole) + fraction.value
        var text = String(format: "%.8f", locale: Locale(identifier: "en_US_POSIX"), value)
        while text.last == "0" { text.removeLast() }
        if text.last == "." { text.removeLast() }
        amount = text
    }

    private var selectedPortion: FoodPortion? {
        guard let food = selectedFood else { return nil }
        return selectedPortionID.flatMap { id in food.portions.first { $0.id == id } } ?? food.defaultPortion
    }

    private var selectedPortionBaseAmount: Double? {
        guard let food = selectedFood, let portion = selectedPortion else { return nil }
        return portion.baseAmount(in: food.unit)
    }

    /// Only an explicit tap on the unit picker converts the visible input.
    /// Selecting a food programmatically must keep "1 portion" as 1 portion.
    private var foodAmountModeSelection: Binding<Int> {
        Binding(
            get: { foodAmountMode },
            set: { newMode in
                guard newMode != foodAmountMode else { return }
                defer { foodAmountMode = newMode }
                guard let servingSize = selectedPortionBaseAmount,
                      servingSize > 0,
                      let current = decimal(amount),
                      let food = selectedFood else { return }
                if newMode == 1 {
                    let canonical = preferredDisplayUnit(for: food).converted(current, to: food.unit) ?? current
                    amount = formattedAmount(canonical / servingSize)
                } else {
                    let canonical = current * servingSize
                    amount = formattedAmount(food.unit.converted(canonical, to: preferredDisplayUnit(for: food)) ?? canonical)
                }
            }
        )
    }

    private var entryGrams: Double? {
        let value: Double?
        if let recipe = selectedRecipe, recipeUnit == 0 {
            value = decimal(recipeQuantity).map { $0 * recipe.gramsPerServing }
        } else if selectedFood != nil, foodAmountMode == 1, let servingSize = selectedPortionBaseAmount, servingSize > 0 {
            value = decimal(amount).map { $0 * servingSize }
        } else if let displayedAmount = decimal(amount) {
            if let food = selectedFood {
                value = preferredDisplayUnit(for: food).converted(displayedAmount, to: food.unit)
            } else if selectedRecipe != nil {
                value = userSettings.defaultFoodUnit.converted(displayedAmount, to: .gram)
            } else {
                value = displayedAmount
            }
        } else {
            value = nil
        }
        guard let value, FoodAmountLimit.accepts(value) else { return nil }
        return value
    }

    private var visibleAmountLabel: String {
        if selectedRecipe != nil, recipeUnit == 0 { return t("add_entry.amount_servings", recipeQuantity) }
        if selectedFood != nil, foodAmountMode == 1, let portion = selectedPortion { return "\(amount) × \(portion.displayName(using: language))" }
        if let food = selectedFood { return "\(amount) \(preferredDisplayUnit(for: food).rawValue)" }
        return "\(amount) \(userSettings.defaultFoodUnit.rawValue)"
    }

    private func preferredDisplayUnit(for food: FoodItem) -> FoodUnit {
        food.unit.isVolume ? userSettings.defaultLiquidUnit : userSettings.defaultFoodUnit
    }

    private func referenceAmount(for food: FoodItem) -> String {
        food.unit.nutritionReferenceLabel
    }

    private func portionPickerLabel(_ portion: FoodPortion, food: FoodItem) -> String {
        let displayUnit = preferredDisplayUnit(for: food)
        guard let canonical = portion.baseAmount(in: food.unit) else {
            return portion.displayName(using: language)
        }
        let displayed = food.unit.converted(canonical, to: displayUnit) ?? canonical
        return "\(portion.displayName(using: language)) – \(formattedAmount(displayed)) \(displayUnit.rawValue)"
    }

    private var nutrients: CalculatedNutrients? {
        guard let grams = entryGrams else { return nil }
        let values: CalculatedNutrients?
        if let food = selectedFood { values = food.calculatedValues(forGrams: grams) }
        else { values = selectedRecipe.map { $0.nutrientsPer100g.scaled(by: grams / 100) } }
        guard let values, values.kcal.isFinite, abs(values.kcal) < 1_000_000_000 else { return nil }
        return values
    }

    private var actualEntryDate: Date {
        let calendar = Calendar.current
        let now = Date()
        let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: now)
        return calendar.date(bySettingHour: timeComponents.hour ?? 0,
                             minute: timeComponents.minute ?? 0,
                             second: timeComponents.second ?? 0,
                             of: selectedEntryDate) ?? selectedEntryDate
    }

    private func save() {
        guard !isSaving else { return }
        if Calendar.current.startOfDay(for: selectedEntryDate) > Calendar.current.startOfDay(for: Date()), !premium.hasNutrition {
            showingNutritionPremium = true
            return
        }
        guard let grams = entryGrams, grams > 0, nutrients != nil else { return }
        let food = selectedFood.map { foodStore.food(id: $0.id) ?? $0 } ?? recipeFood
        guard let item = food else { return }

        // Zucker-Snapshot in "zugesetzt" vs. "Fruchtzucker" aufteilen.
        var addedSugarPer100g = 0.0
        var fruitSugarPer100g = 0.0
        if let selectedFood {
            if selectedFood.isFruit {
                fruitSugarPer100g = selectedFood.sugarPer100g
            } else {
                addedSugarPer100g = selectedFood.sugarPer100g
            }
        } else if let selectedRecipe {
            let totalGrams = selectedRecipe.totalGrams
            if totalGrams > 0 {
                let addedTotal = selectedRecipe.ingredients.reduce(0.0) { partial, ingredient in
                    partial + (ingredient.food.isFruit ? 0 : ingredient.food.sugarPer100g * ingredient.grams / 100)
                }
                let fruitTotal = selectedRecipe.ingredients.reduce(0.0) { partial, ingredient in
                    partial + (ingredient.food.isFruit ? ingredient.food.sugarPer100g * ingredient.grams / 100 : 0)
                }
                addedSugarPer100g = addedTotal / totalGrams * 100
                fruitSugarPer100g = fruitTotal / totalGrams * 100
            }
        }

        let entry = CalorieEntry(
            foodItemId: selectedFood?.id,
            recipeId: selectedRecipe?.id,
            globalFoodRecordID: selectedFood?.globalRecordID,
            userRecipeRecordID: selectedRecipe?.origin == .personal ? selectedRecipe?.remoteID : nil,
            globalRecipeRecordID: selectedRecipe?.origin == .global ? (selectedRecipe?.globalRecordID ?? selectedRecipe?.remoteID) : selectedRecipe?.globalRecordID,
            name: item.name,
            grams: grams,
            categoryId: selectedCategory.id,
            categoryName: selectedCategory.storageKey,
            portionName: foodAmountMode == 1 ? selectedPortion?.displayName(using: language) : nil,
            portionID: foodAmountMode == 1 ? selectedPortion?.id : nil,
            portionCount: foodAmountMode == 1 ? decimal(amount) : nil,
            unit: selectedFood?.unit ?? .gram,
            kcalPer100g: item.kcalPer100g,
            carbsPer100g: item.carbsPer100g,
            proteinPer100g: item.proteinPer100g,
            fatPer100g: item.fatPer100g,
            addedSugarPer100g: addedSugarPer100g,
            fruitSugarPer100g: fruitSugarPer100g,
            fiberPer100g: item.fiberPer100g,
            saturatedFatPer100g: item.saturatedFatPer100g,
            saltPer100g: item.saltPer100g,
            micronutrients: item.micronutrients,
            date: actualEntryDate
        )

        let pendingAmountText: String
        let usesPortion = selectedFood != nil && foodAmountMode == 1
        if selectedFood != nil {
            pendingAmountText = amount
        } else {
            let displayUnit = userSettings.defaultFoodUnit
            let displayedAmount = entry.unit.converted(entry.grams, to: displayUnit) ?? entry.grams
            pendingAmountText = formattedAmount(displayedAmount)
        }
        pendingEntries.append(PendingFoodEntry(entry: entry, food: selectedFood, amountText: pendingAmountText, usesPortion: usesPortion))
        persistPendingDraft()
        selectedFood = nil
        selectedRecipe = nil
        selectedPortionID = nil
        foodAmountMode = 0
        amount = "100"
        recipeQuantity = "1"
    }

    private func savePendingEntries(confirmedOverGoal: Bool = false) {
        removeCommittedPendingEntries()
        guard !pendingEntries.isEmpty, !isSaving else { return }
        for index in pendingEntries.indices {
            guard applyPendingAmount(at: index) else {
                alertMessage = t("add_entry.amount_limit")
                return
            }
        }
        if Calendar.current.startOfDay(for: selectedEntryDate) > Calendar.current.startOfDay(for: Date()), !premium.hasNutrition {
            showingNutritionPremium = true
            return
        }
        if let restriction = calorieStore.trackingRestriction(for: selectedEntryDate) {
            alertMessage = restriction.message(using: language)
            return
        }

        let timestamp = actualEntryDate
        let entries = pendingEntries.map { pending -> CalorieEntry in
            var entry = pending.entry
            entry.categoryId = selectedCategory.id
            entry.categoryName = selectedCategory.storageKey
            entry.date = timestamp
            return entry
        }
        let incomingCalories = entries.reduce(0) { $0 + $1.kcal }
        let selectedDayAllowance = calorieStore.calorieAllowance(for: selectedEntryDate) ?? availableCalories
        if userSettings.enforceCalorieLimit,
           calorieStore.totalKcal(for: selectedEntryDate) + incomingCalories > userSettings.maximumAllowedCalories(selectedDayAllowance) {
            alertMessage = t("add_entry.daily_limit_exceeded")
            return
        }
        let categoryCurrent = calorieStore.totalKcal(for: selectedEntryDate, categoryId: selectedCategory.id)
        if selectedCategory.enforceLimit,
           let limit = selectedCategory.limit(for: selectedDayAllowance),
           categoryCurrent + incomingCalories > limit {
            alertMessage = t("add_entry.meal_limit_exceeded", selectedCategory.localizedName, Int(limit))
            return
        }
        if !userSettings.enforceCalorieLimit, !confirmedOverGoal,
           selectedDayAllowance > 0,
           calorieStore.totalKcal(for: selectedEntryDate) + incomingCalories > selectedDayAllowance {
            calorieGoalOverage = (calorieStore.totalKcal(for: selectedEntryDate) + incomingCalories - selectedDayAllowance).rounded(.up).safeIntValue
            showingCalorieGoalWarning = true
            return
        }

        isSaving = true
        guard calorieStore.addEntries(entries) else {
            isSaving = false
            if let restriction = calorieStore.lastFoodTrackingRestriction {
                alertMessage = restriction.message(using: language)
            } else if calorieStore.lastLocalSaveFailed {
                alertMessage = t("add_entry.local_save_failed")
            }
            return
        }
        let savedPendingEntries = pendingEntries
        pendingEntries.removeAll()
        reviewingPendingEntries = false
        clearPendingDraft()
        for (pending, entry) in zip(savedPendingEntries, entries) {
            if let food = pending.food {
                frequencyStore.recordUsage(food: food, categoryId: selectedCategory.id)
                accountData.recordUsage(
                    food: food,
                    amount: entry.grams,
                    mealKey: selectedCategory.storageKey,
                    portionID: entry.portionID,
                    portionCount: entry.portionCount,
                    usedAt: timestamp
                )
            } else if let recipeID = entry.recipeId {
                frequencyStore.recordUsage(itemId: recipeID, categoryId: selectedCategory.id)
            }
        }
        dismiss()
    }

    @discardableResult
    private func applyPendingAmount(at index: Int) -> Bool {
        guard pendingEntries.indices.contains(index) else { return false }
        let pending = pendingEntries[index]
        guard let displayedAmount = decimal(pending.amountText), displayedAmount > 0 else { return false }

        var entry = pending.entry
        if pending.usesPortion,
           let food = pending.food,
           let portionID = entry.portionID,
           let portion = food.portions.first(where: { $0.id == portionID }),
           let portionAmount = portion.baseAmount(in: entry.unit),
           portionAmount > 0 {
            entry.grams = displayedAmount * portionAmount
            entry.portionCount = displayedAmount
        } else {
            let displayUnit = pending.food.map(preferredDisplayUnit(for:)) ?? userSettings.defaultFoodUnit
            entry.grams = displayUnit.converted(displayedAmount, to: entry.unit) ?? displayedAmount
            entry.portionID = nil
            entry.portionName = nil
            entry.portionCount = nil
        }
        pendingEntries[index].entry = entry
        return FoodAmountLimit.accepts(entry.grams) && entry.kcal.isFinite && abs(entry.kcal) < 1_000_000_000
    }

    private static func loadPendingDraft(excluding committedIDs: Set<UUID>) -> PendingFoodEntryDraft? {
        guard let data = UserDefaults.standard.data(forKey: pendingDraftKey) else { return nil }
        guard var draft = try? JSONDecoder().decode(PendingFoodEntryDraft.self, from: data) else { return nil }
        let originalCount = draft.entries.count
        draft.entries.removeAll { committedIDs.contains($0.id) }
        guard draft.entries.count != originalCount else { return draft }
        if draft.entries.isEmpty {
            UserDefaults.standard.removeObject(forKey: pendingDraftKey)
            _ = UserDefaults.standard.synchronize()
            return nil
        }
        if let updatedData = try? JSONEncoder().encode(draft) {
            UserDefaults.standard.set(updatedData, forKey: pendingDraftKey)
            _ = UserDefaults.standard.synchronize()
        }
        return draft
    }

    private func persistPendingDraft() {
        guard foodSelectionHandler == nil else { return }
        let committedIDs = Set(calorieStore.entries.map(\.id))
        let uncommittedEntries = pendingEntries.filter { !committedIDs.contains($0.id) }
        guard !uncommittedEntries.isEmpty else {
            clearPendingDraft()
            return
        }
        let draft = PendingFoodEntryDraft(
            categoryID: selectedCategory.id,
            entryDate: selectedEntryDate,
            entries: uncommittedEntries,
            isReviewing: reviewingPendingEntries
        )
        guard let data = try? JSONEncoder().encode(draft) else { return }
        UserDefaults.standard.set(data, forKey: Self.pendingDraftKey)
    }

    private func clearPendingDraft() {
        UserDefaults.standard.removeObject(forKey: Self.pendingDraftKey)
        _ = UserDefaults.standard.synchronize()
    }

    private var recipeFood: FoodItem? { selectedRecipe.map { recipe in
        FoodItem(name: recipe.name, kcalPer100g: recipe.nutrientsPer100g.kcal, carbsPer100g: recipe.nutrientsPer100g.carbs, proteinPer100g: recipe.nutrientsPer100g.protein, fatPer100g: recipe.nutrientsPer100g.fat, sugarPer100g: recipe.nutrientsPer100g.sugar, fiberPer100g: recipe.nutrientsPer100g.fiber, saturatedFatPer100g: recipe.nutrientsPer100g.saturatedFat, saltPer100g: recipe.nutrientsPer100g.salt, micronutrients: MicronutrientProfile.combined(recipe.ingredients.map { ($0.food.micronutrients, $0.grams) }, totalGrams: recipe.totalGrams))
    } }
}

private extension Double {
    var clean: String {
        truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", self) : String(format: "%.1f", self)
    }
}
