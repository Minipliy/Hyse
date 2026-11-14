import SwiftUI
import UIKit
import AVFoundation

private struct BatchFoodDraft: Identifiable {
    let id = UUID()
    let entryID = UUID()
    let food: FoodItem
    var amount: String
}

struct BatchAddEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var language: LanguageStore
    @ObservedObject var foodStore: FoodStore
    @ObservedObject var categoryStore: CategoryStore
    @ObservedObject var calorieStore: CalorieStore
    @ObservedObject var accountData: AccountDataStore
    @ObservedObject var userSettings: UserSettingsStore
    @ObservedObject var frequencyStore: FrequencyStore

    @State private var category: MealCategory
    @State private var date: Date
    @State private var query = ""
    @State private var drafts: [BatchFoodDraft] = []
    @State private var reviewing = false
    @State private var isPreparingReview = false
    @State private var isSaving = false
    @State private var validationMessage: String?
    @State private var filter = 1
    @State private var visibleFoods: [FoodItem] = []
    @State private var isPreparingFoodResults = true
    @State private var isSearchingRemoteFoods = false
    @State private var showingCreateFoodSheet = false
    @State private var newFoodInitialName = ""
    @State private var scannedBarcodeForNewFood = ""
    @State private var scannedExternalDraft: FoodItem?
    @State private var showingBarcodeScanner = false
    @State private var showingCameraExplanation = false
    @State private var showingCameraDenied = false
    @State private var showingManualBarcode = false
    @State private var manualBarcode = ""
    @State private var scannerTorchOn = false
    @State private var isLoadingBarcode = false
    @State private var alertMessage: String?
    @State private var barcodeConfirmation: String?
    @State private var barcodeConfirmationTask: Task<Void, Never>?
    @State private var recentSearchedFoodKeys: [String]
    @FocusState private var searchFocused: Bool

    private static let recentSearchedFoodsKey = "recent_searched_food_ids_v1"
    private static let stableRecentSearchedFoodsKey = "recent_searched_food_keys_v2"

    init(foodStore: FoodStore, categoryStore: CategoryStore, calorieStore: CalorieStore, accountData: AccountDataStore, userSettings: UserSettingsStore, frequencyStore: FrequencyStore, initialCategory: MealCategory, entryDate: Date) {
        self.foodStore = foodStore
        self.categoryStore = categoryStore
        self.calorieStore = calorieStore
        self.accountData = accountData
        self.userSettings = userSettings
        self.frequencyStore = frequencyStore
        _category = State(initialValue: initialCategory)
        _date = State(initialValue: entryDate)
        let stored = UserDefaults.standard.stringArray(forKey: Self.stableRecentSearchedFoodsKey)
            ?? UserDefaults.standard.stringArray(forKey: Self.recentSearchedFoodsKey)
            ?? []
        _recentSearchedFoodKeys = State(initialValue: stored.map { value in
            UUID(uuidString: value)?.uuidString.lowercased() ?? value
        })
    }

    private func t(_ key: String, _ arguments: CVarArg...) -> String { language.text(key, arguments) }
    private var results: [FoodItem] { visibleFoods }

    var body: some View {
        NavigationStack {
            List {
                if isPreparingReview {
                    preparingReviewContent
                } else if reviewing {
                    reviewContent
                } else {
                    searchContent
                }
            }
            .id(isPreparingReview ? "batch-preparing" : (reviewing ? "batch-review" : "batch-search"))
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background { HyseBackdrop() }
            .hyseForm()
            .navigationTitle(t("batch_add.title"))
            .task(id: "\(reviewing)|\(isPreparingReview)|\(filter)|\(query)|\(frequencyStore.revision)|\(foodStore.globalFoods.count)") {
                guard !reviewing, !isPreparingReview else { return }
                await refreshFoodResults()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("app_tabs.cancel")) { dismiss() }.disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(reviewing ? t("batch_add.save_count", drafts.count) : t("batch_add.review_count", drafts.count)) {
                        reviewing ? save() : beginReview()
                    }
                    .disabled(drafts.isEmpty || isSaving || isPreparingReview)
                }
            }
            .hyseAlert(isPresented: Binding(get: { validationMessage != nil }, set: { if !$0 { validationMessage = nil } }), title: t("ui.notice"), message: validationMessage ?? "", buttonTitle: t("common.ok"))
            .sheet(isPresented: $showingCreateFoodSheet) {
                CreateFoodView(
                    foodStore: foodStore,
                    barcode: scannedBarcodeForNewFood,
                    draft: scannedExternalDraft,
                    initialName: newFoodInitialName
                ) { newFood in
                    let createdFromBarcode = !scannedBarcodeForNewFood.isEmpty
                    scannedBarcodeForNewFood = ""
                    scannedExternalDraft = nil
                    newFoodInitialName = ""
                    addIfNeeded(newFood)
                    if createdFromBarcode { showBarcodeConfirmation(for: newFood, wasAlreadySelected: false) }
                }
            }
            .sheet(isPresented: $showingBarcodeScanner) { barcodeScannerSheet }
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
                TextField(t("barcode.manual_placeholder"), text: $manualBarcode).keyboardType(.numberPad)
                Button(t("app_tabs.cancel"), role: .cancel) { manualBarcode = "" }
                Button(t("barcode.lookup")) {
                    let code = manualBarcode
                    manualBarcode = ""
                    handleBarcode(code)
                }
            } message: { Text(t("barcode.manual_explanation")) }
            .alert(t("ui.notice"), isPresented: Binding(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } })) {
                Button(t("common.ok")) { alertMessage = nil }
            } message: { Text(alertMessage ?? "") }
            .onChange(of: foodStore.foods) { _, _ in
                guard !reviewing else { return }
                Task { await refreshFoodResults(loadRemote: false) }
            }
            .overlay(alignment: .top) {
                if let barcodeConfirmation {
                    Label(barcodeConfirmation, systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .padding(.horizontal, HyseSpacing.medium)
                        .padding(.vertical, HyseSpacing.small)
                        .hyseGlassSurface(radius: HyseRadius.control, tint: HyseColor.success)
                        .shadow(color: .black.opacity(0.16), radius: 12, y: 6)
                        .padding(.horizontal, HyseSpacing.page)
                        .padding(.top, HyseSpacing.small)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .allowsHitTesting(false)
                        .zIndex(10)
                }
            }
            .sensoryFeedback(.success, trigger: barcodeConfirmation)
            .overlay {
                if isPreparingReview {
                    ZStack {
                        Color.black.opacity(0.18).ignoresSafeArea()
                        ProgressView(t("batch_add.preparing_review"))
                            .padding(HyseSpacing.large)
                                .background(HyseColor.surface, in: RoundedRectangle(cornerRadius: HyseRadius.card, style: .continuous))
                    }
                    .allowsHitTesting(true)
                }
            }
            .onDisappear { barcodeConfirmationTask?.cancel() }
        }
    }

    @ViewBuilder private var searchContent: some View {
        HStack(spacing: HyseSpacing.medium) {
            Image(systemName: "magnifyingglass")
                .font(.title3)
                .foregroundStyle(.secondary)
            TextField(t("add_entry.search_food"), text: $query)
                .focused($searchFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .submitLabel(.search)
                .simultaneousGesture(TapGesture().onEnded { selectAllSearchText() })
                .onChange(of: searchFocused) { _, isFocused in
                    if isFocused { selectAllSearchText() }
                }
            HyseInfoButton(title: t("add_entry.search_food"), message: t("info.food_search.body"))
            Button { beginBarcodeScan() } label: {
                Image(systemName: "barcode.viewfinder").frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(t("barcode.search_existing"))
        }
        .padding(.horizontal, HyseSpacing.medium)
        .padding(.vertical, HyseSpacing.small)
        .hyseGlassSurface(radius: HyseRadius.control)
        .overlay {
            RoundedRectangle(cornerRadius: HyseRadius.control, style: .continuous)
                .stroke(HyseColor.accent, lineWidth: searchFocused ? 2 : 1)
        }
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
                        .foregroundStyle(HyseColor.accent)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: HyseSpacing.small) {
                        ForEach(recentSearchedFoods) { food in
                            Button {
                                rememberSearchedFood(food)
                                toggle(food)
                            } label: {
                                HStack(spacing: HyseSpacing.xSmall) {
                                    Image(systemName: isSelected(food) ? "checkmark.circle.fill" : "fork.knife")
                                        .font(.caption)
                                    Text(food.displayName(using: language)).font(.subheadline.weight(.medium)).lineLimit(1)
                                }
                                .foregroundStyle(isSelected(food) ? HyseColor.accent : Color.primary)
                                .padding(.horizontal, HyseSpacing.medium)
                                .frame(height: 38)
                                .background(HyseColor.surface, in: Capsule())
                                .overlay(Capsule().stroke(isSelected(food) ? HyseColor.accent : HyseColor.border))
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
            Menu {
                Button(t("ui.recent")) { filter = 0 }
                Button(t("ui.frequent")) { filter = 1 }
                Button(t("ui.favourites")) { filter = 2 }
                Button(t("ui.all")) { filter = 3 }
            } label: {
                let keys = ["ui.recent", "ui.frequent", "ui.favourites", "ui.all"]
                searchSelector(title: t(keys[min(max(filter, 0), 3)]), icon: "line.3.horizontal.decrease")
            }
            if !drafts.isEmpty {
                Button {
                    beginReview()
                } label: {
                    Label("\(drafts.count)", systemImage: "cart.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(HyseColor.accent)
                        .padding(.horizontal, HyseSpacing.medium)
                        .frame(minHeight: 44)
                        .background(HyseColor.accent.opacity(0.12), in: Capsule())
                        .contentShape(Capsule())
                }
                .accessibilityLabel(t("batch_add.review_count", drafts.count))
            }
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 0, leading: HyseSpacing.page, bottom: HyseSpacing.medium, trailing: HyseSpacing.page))

        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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
            .frame(minHeight: 22)
            .listRowBackground(Color.clear)
            .accessibilityElement(children: .combine)
            .accessibilityHidden(!isPreparingFoodResults && !isSearchingRemoteFoods)
        }

        if results.isEmpty,
           !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !isPreparingFoodResults,
           !isSearchingRemoteFoods {
            HyseEmptyState(
                icon: "fork.knife.circle",
                title: t("add_entry.no_food_found"),
                message: t("add_entry.create_food_from_search"),
                actionTitle: t("ui.create_new_food"),
                action: createFoodFromCurrentSearch
            )
            .listRowBackground(Color.clear)
        } else {
            Section(t("batch_add.available_foods")) {
                ForEach(results) { food in batchFoodRow(food) }
            }
        }
    }

    @ViewBuilder private var reviewContent: some View {
        Section(t("batch_add.common_details")) {
            Picker(t("ui.category"), selection: $category) {
                ForEach(categoryStore.categories) { Text($0.localizedName).tag($0) }
            }
            DatePicker(t("content.calendar"), selection: $date, displayedComponents: .date)
        }
        Section(t("batch_add.selected_foods")) {
            ForEach($drafts) { $draft in
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(draft.food.displayName(using: language))
                        Text("\(Int(draft.food.kcalPerNutritionReference)) kcal / \(referenceAmount(for: draft.food))").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    TextField("100", text: $draft.amount)
                        .textFieldStyle(.plain)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .padding(.vertical, 3)
                        .padding(.horizontal, 4)
                        .background(Color.clear)
                        .frame(width: 72)
                        .accessibilityLabel(t("recipe_editor.amount"))
                    Text(displayUnit(for: draft.food).rawValue).foregroundStyle(.secondary)
                    Button(role: .destructive) { drafts.removeAll { $0.id == draft.id } } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(t("settings.delete"))
                }
            }
            Button { reviewing = false } label: { Label(t("batch_add.add_more"), systemImage: "plus") }
        }
    }

    @ViewBuilder private var preparingReviewContent: some View {
        HStack(spacing: HyseSpacing.medium) {
            ProgressView()
            VStack(alignment: .leading, spacing: HyseSpacing.xSmall) {
                Text(t("batch_add.preparing_review"))
                    .font(.headline)
                Text(t("batch_add.selected_foods_count", drafts.count))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, HyseSpacing.large)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private func searchSelector(title: String, icon: String) -> some View {
        HStack(spacing: HyseSpacing.small) {
            Image(systemName: icon).foregroundStyle(HyseColor.accent)
            Text(title).font(.subheadline.weight(.semibold)).lineLimit(1)
            Spacer(minLength: 0)
            Image(systemName: "chevron.down").font(.caption).foregroundStyle(.secondary)
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, HyseSpacing.medium)
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(HyseColor.surface, in: RoundedRectangle(cornerRadius: HyseRadius.control, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: HyseRadius.control, style: .continuous).stroke(HyseColor.border) }
    }

    private func batchFoodRow(_ food: FoodItem) -> some View {
        Button {
            if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { rememberSearchedFood(food) }
            toggle(food)
        } label: {
            HStack(spacing: HyseSpacing.medium) {
                Image(systemName: isSelected(food) ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected(food) ? HyseColor.accent : .secondary)
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
                    Text([food.brand, referenceAmount(for: food)].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(Int(food.kcalPerNutritionReference)) kcal")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, HyseSpacing.xSmall)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(isSelected(food) ? t("add_entry.selected") : t("add_entry.not_selected"))
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

    private func beginReview() {
        guard !drafts.isEmpty, !isPreparingReview else { return }
        searchFocused = false
        isPreparingReview = true
        Task { @MainActor in
            // Give SwiftUI one display frame for the lightweight preparation
            // state. This also cancels an in-flight remote search before the
            // review list is built.
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return }
            reviewing = true
            isPreparingReview = false
        }
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
        let recentEntries = calorieStore.entries.filter { $0.recipeId == nil }.sorted { $0.date > $1.date }
        let recentIDs = recentEntries.compactMap(\.foodItemId) + frequencyStore.recentItemIDs
        let sourceCounts = frequencyStore.sourceTotalCounts
        let recentSources = recentEntries.compactMap { entry -> String? in
            if let globalID = entry.globalFoodRecordID { return "global_food:\(globalID)" }
            if let foodID = entry.foodItemId { return "user_food:\(foodID.uuidString.lowercased())" }
            return nil
        } + frequencyStore.recentSourceKeys
        let favoriteIDs = Set(localSnapshot.lazy.filter { foodStore.isFavorite($0) }.map(\.id))
        let localResults = await Task.detached(priority: .userInitiated) {
            Self.makeVisibleFoods(
                from: localSnapshot,
                query: requestedQuery,
                filter: requestedFilter,
                usageCounts: counts,
                recentIDs: recentIDs,
                sourceUsageCounts: sourceCounts,
                recentSourceKeys: recentSources,
                favoriteIDs: favoriteIDs
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
        let refreshedFavorites = Set(refreshedSnapshot.lazy.filter { foodStore.isFavorite($0) }.map(\.id))
        let refreshedResults = await Task.detached(priority: .userInitiated) {
            Self.makeVisibleFoods(
                from: refreshedSnapshot,
                query: requestedQuery,
                filter: requestedFilter,
                usageCounts: counts,
                recentIDs: recentIDs,
                sourceUsageCounts: sourceCounts,
                recentSourceKeys: recentSources,
                favoriteIDs: refreshedFavorites
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
        recentSourceKeys: [String],
        favoriteIDs: Set<UUID>
    ) -> [FoodItem] {
        func usageCount(_ food: FoodItem) -> Int {
            max(usageCounts[food.id, default: 0], sourceUsageCounts[FrequencyStore.sourceKey(for: food), default: 0])
        }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return Array(foods.lazy.filter { food in
                FoodSearchRanker.matches(food, query: trimmed)
                    && (filter != 2 || favoriteIDs.contains(food.id))
            }
            .sorted {
                let leftScore = FoodSearchRanker.relevanceScore($0, query: trimmed)
                let rightScore = FoodSearchRanker.relevanceScore($1, query: trimmed)
                if leftScore != rightScore { return leftScore < rightScore }
                if filter == 1 {
                    let leftCount = usageCount($0)
                    let rightCount = usageCount($1)
                    if leftCount != rightCount { return leftCount > rightCount }
                }
                let leftFavorite = favoriteIDs.contains($0.id)
                let rightFavorite = favoriteIDs.contains($1.id)
                if filter != 2, leftFavorite != rightFavorite { return leftFavorite }
                return FoodSearchRanker.orderedBefore($0, $1, query: trimmed)
            }
            .prefix(120))
        }

        let ranks = recentIDs.enumerated().reduce(into: [UUID: Int]()) { result, value in
            if result[value.element] == nil { result[value.element] = value.offset }
        }
        let sourceRanks = recentSourceKeys.enumerated().reduce(into: [String: Int]()) { result, value in
            if result[value.element] == nil { result[value.element] = value.offset }
        }
        func rank(_ food: FoodItem) -> Int {
            min(ranks[food.id, default: .max], sourceRanks[FrequencyStore.sourceKey(for: food), default: .max])
        }
        switch filter {
        case 0:
            return Array(foods.lazy.filter { rank($0) != .max }.sorted {
                rank($0) < rank($1)
            })
        case 1:
            return Array(foods.lazy.filter {
                usageCount($0) > 0 || rank($0) != .max
            }.sorted {
                let leftCount = usageCount($0)
                let rightCount = usageCount($1)
                if leftCount != rightCount { return leftCount > rightCount }
                let leftRank = rank($0)
                let rightRank = rank($1)
                if leftRank != rightRank { return leftRank < rightRank }
                let leftFavorite = favoriteIDs.contains($0.id)
                let rightFavorite = favoriteIDs.contains($1.id)
                if leftFavorite != rightFavorite { return leftFavorite }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            })
        case 2:
            return Array(foods.lazy.filter { favoriteIDs.contains($0.id) }.prefix(120))
        default:
            return Array(foods.sorted {
                let leftFavorite = favoriteIDs.contains($0.id)
                let rightFavorite = favoriteIDs.contains($1.id)
                if leftFavorite != rightFavorite { return leftFavorite }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }.prefix(120))
        }
    }

    private func createFoodFromCurrentSearch() {
        newFoodInitialName = query.trimmingCharacters(in: .whitespacesAndNewlines)
        scannedBarcodeForNewFood = ""
        scannedExternalDraft = nil
        showingCreateFoodSheet = true
    }

    private var barcodeScannerSheet: some View {
        NavigationStack {
            ZStack {
                BarcodeScannerView(
                    torchOn: $scannerTorchOn,
                    onScanned: handleBarcode,
                    onError: { error in
                        showingBarcodeScanner = false
                        alertMessage = error
                    }
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(.white, lineWidth: 3)
                        .frame(width: 280, height: 170)
                        .shadow(color: .black.opacity(0.55), radius: 5)
                        .accessibilityHidden(true)
                }

                if isLoadingBarcode {
                    Color.black.opacity(0.38).ignoresSafeArea()
                    ProgressView(t("barcode.checking_hyse"))
                        .padding(HyseSpacing.large)
                        .background(HyseColor.surface, in: RoundedRectangle(cornerRadius: HyseRadius.card, style: .continuous))
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: HyseSpacing.large) {
                    Button { scannerTorchOn.toggle() } label: {
                        Label(t("barcode.flashlight"), systemImage: scannerTorchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                    }
                    Button {
                        showingBarcodeScanner = false
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(220))
                            showingManualBarcode = true
                        }
                    } label: {
                        Label(t("barcode.enter_manually"), systemImage: "keyboard")
                    }
                }
                .buttonStyle(.borderedProminent)
                .padding()
                .frame(maxWidth: .infinity)
                .background(HyseColor.background)
            }
            .navigationTitle(t("ui.scan_barcode"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("app_tabs.cancel")) { showingBarcodeScanner = false }
                }
            }
        }
        .interactiveDismissDisabled(isLoadingBarcode)
    }

    private func beginBarcodeScan() {
        scannerTorchOn = false
        isLoadingBarcode = false
        manualBarcode = ""
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: showingBarcodeScanner = true
        case .notDetermined: showingCameraExplanation = true
        case .denied, .restricted: showingCameraDenied = true
        @unknown default: showingCameraDenied = true
        }
    }

    private func requestCameraAccess() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                if granted { showingBarcodeScanner = true }
                else { showingCameraDenied = true }
            }
        }
    }

    private func handleBarcode(_ code: String) {
        let normalized: String
        do { normalized = try BarcodeNormalizer.normalize(code) }
        catch { alertMessage = error.localizedDescription; return }

        isLoadingBarcode = true
        Task {
            let cachedMatches = foodStore.barcodeMatches(normalized)
            if cachedMatches.count == 1, let knownFood = cachedMatches.first {
                finishBarcodeLookup(with: knownFood)
                return
            }
            if cachedMatches.count > 1 {
                finishBarcodeLookupWithConflict()
                return
            }

            let externalTask = Task { try? await OpenFoodFactsService.shared.fetchProduct(barcode: normalized) }
            let matches = await foodStore.lookupKnownBarcode(normalized)
            if matches.count == 1, let knownFood = matches.first {
                externalTask.cancel()
                finishBarcodeLookup(with: knownFood)
                return
            }
            if matches.count > 1 {
                externalTask.cancel()
                finishBarcodeLookupWithConflict()
                return
            }

            let fetched = await externalTask.value
            isLoadingBarcode = false
            showingBarcodeScanner = false
            scannedExternalDraft = fetched
            scannedBarcodeForNewFood = normalized
            newFoodInitialName = ""
            try? await Task.sleep(for: .milliseconds(100))
            showingCreateFoodSheet = true
        }
    }

    private func finishBarcodeLookup(with food: FoodItem) {
        isLoadingBarcode = false
        showingBarcodeScanner = false
        let wasAlreadySelected = isSelected(food)
        addIfNeeded(food)
        showBarcodeConfirmation(for: food, wasAlreadySelected: wasAlreadySelected)
    }

    private func finishBarcodeLookupWithConflict() {
        isLoadingBarcode = false
        showingBarcodeScanner = false
        alertMessage = t("barcode.conflicting_matches")
    }

    private func isSelected(_ food: FoodItem) -> Bool { drafts.contains { $0.food.id == food.id } }

    private func addIfNeeded(_ food: FoodItem) {
        guard !isSelected(food) else { return }
        toggle(food)
    }

    private func showBarcodeConfirmation(for food: FoodItem, wasAlreadySelected: Bool) {
        barcodeConfirmationTask?.cancel()
        let key = wasAlreadySelected ? "batch_add.barcode_already_added" : "batch_add.barcode_added"
        withAnimation(HyseMotion.standard) {
            barcodeConfirmation = t(key, food.displayName(using: language))
        }
        barcodeConfirmationTask = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(2)) }
            catch { return }
            withAnimation(HyseMotion.standard) { barcodeConfirmation = nil }
        }
    }

    private func toggle(_ food: FoodItem) {
        if let index = drafts.firstIndex(where: { $0.food.id == food.id }) {
            drafts.remove(at: index)
        } else {
            let suggestion = accountData.suggestion(for: food)
            let displayedAmount = suggestion.unit.converted(suggestion.amount, to: displayUnit(for: food)) ?? suggestion.amount
            drafts.append(BatchFoodDraft(food: food, amount: formatted(displayedAmount)))
        }
    }

    private func selectAllSearchText() {
        guard !query.isEmpty else { return }
        DispatchQueue.main.async {
            UIApplication.shared.sendAction(#selector(UIResponder.selectAll(_:)), to: nil, from: nil, for: nil)
        }
    }

    private func save() {
        guard !isSaving else { return }
        if let restriction = calorieStore.trackingRestriction(for: date) {
            validationMessage = restriction.message(using: language)
            return
        }
        let values = drafts.compactMap { draft -> (BatchFoodDraft, Double)? in
            guard let displayedAmount = Double(draft.amount.replacingOccurrences(of: ",", with: ".")), displayedAmount > 0,
                  let amount = displayUnit(for: draft.food).converted(displayedAmount, to: draft.food.unit),
                  FoodAmountLimit.accepts(amount),
                  (draft.food.kcalPer100g * amount / 100).isFinite,
                  abs(draft.food.kcalPer100g * amount / 100) < 1_000_000_000 else { return nil }
            return (draft, amount)
        }
        guard values.count == drafts.count else { validationMessage = t("add_entry.amount_limit"); return }
        isSaving = true
        let calendar = Calendar.current
        let now = Date()
        let time = calendar.dateComponents([.hour, .minute, .second], from: now)
        let timestamp = calendar.date(bySettingHour: time.hour ?? 12, minute: time.minute ?? 0, second: time.second ?? 0, of: date) ?? date
        let entries = values.map { draft, amount in
            CalorieEntry(
                id: draft.entryID, foodItemId: draft.food.id, globalFoodRecordID: draft.food.globalRecordID,
                name: draft.food.name, grams: amount, categoryId: category.id, categoryName: category.storageKey,
                unit: draft.food.unit, kcalPer100g: draft.food.kcalPer100g, carbsPer100g: draft.food.carbsPer100g,
                proteinPer100g: draft.food.proteinPer100g, fatPer100g: draft.food.fatPer100g,
                addedSugarPer100g: draft.food.isFruit ? 0 : draft.food.sugarPer100g,
                fruitSugarPer100g: draft.food.isFruit ? draft.food.sugarPer100g : 0,
                fiberPer100g: draft.food.fiberPer100g, saturatedFatPer100g: draft.food.saturatedFatPer100g,
                saltPer100g: draft.food.saltPer100g, date: timestamp
            )
        }
        guard calorieStore.addEntries(entries) else {
            isSaving = false
            if let restriction = calorieStore.lastFoodTrackingRestriction {
                validationMessage = restriction.message(using: language)
            } else if calorieStore.lastLocalSaveFailed {
                validationMessage = t("add_entry.local_save_failed")
            }
            return
        }
        values.forEach {
            frequencyStore.recordUsage(food: $0.0.food, categoryId: category.id)
            accountData.recordUsage(food: $0.0.food, amount: $0.1, mealKey: category.storageKey, usedAt: timestamp)
        }
        dismiss()
    }

    private func formatted(_ value: Double) -> String {
        guard value.isFinite else { return "0" }
        if value.rounded() == value, let integer = Int(exactly: value) { return String(integer) }
        return String(format: "%.2f", locale: language.locale, value)
    }

    private func displayUnit(for food: FoodItem) -> FoodUnit {
        food.unit.isVolume ? userSettings.defaultLiquidUnit : userSettings.defaultFoodUnit
    }


    private func referenceAmount(for food: FoodItem) -> String {
        food.unit.nutritionReferenceLabel
    }
}
