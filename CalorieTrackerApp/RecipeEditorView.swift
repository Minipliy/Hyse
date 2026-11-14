import SwiftUI
import AVFoundation
import UIKit
import PhotosUI

private struct EditableRecipeStep: Identifiable {
    let id = UUID()
    var text: String
}

struct RecipeEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var language: LanguageStore
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var categoryStore: CategoryStore
    @EnvironmentObject private var frequencyStore: FrequencyStore
    @EnvironmentObject private var userSettings: UserSettingsStore
    @EnvironmentObject private var calorieStore: CalorieStore
    @ObservedObject var foodStore: FoodStore
    @ObservedObject var recipeStore: RecipeStore
    var recipe: Recipe?
    @State private var name = ""
    @State private var description = ""
    @State private var steps: [EditableRecipeStep] = []
    @State private var photoItem: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var photoChanged = false
    @State private var photoError = false
    @State private var servings = "1"
    @State private var ingredients: [RecipeIngredient] = []
    @State private var showingPicker = false
    @State private var ingredientToInspect: RecipeIngredient?
    @State private var selectedFilters: Set<RecipeFilter> = []
    @State private var totalWeight = ""
    @State private var preparationMinutes = ""
    @State private var tags = ""
    private func t(_ key: String, _ arguments: CVarArg...) -> String { language.text(key, arguments) }

    init(foodStore: FoodStore, recipeStore: RecipeStore, recipe: Recipe? = nil) {
        self.foodStore = foodStore; self.recipeStore = recipeStore; self.recipe = recipe
        _name = State(initialValue: recipe?.name ?? "")
        _description = State(initialValue: recipe?.recipeDescription ?? "")
        _steps = State(initialValue: (recipe?.preparationSteps ?? []).map { EditableRecipeStep(text: $0) })
        _photoData = State(initialValue: RecipeImageStore.data(for: recipe?.imageFileName)
            ?? RecipeImageStore.cachedRemoteData(remoteID: recipe?.remoteID, fileName: recipe?.remoteImageFileName))
        _servings = State(initialValue: (recipe?.servings ?? 1).formatted(.number.precision(.fractionLength(0...1))))
        _ingredients = State(initialValue: recipe?.ingredients ?? [])
        _selectedFilters = State(initialValue: recipe?.filters ?? [])
        _totalWeight = State(initialValue: recipe?.totalWeightGrams.map { String(format: "%.0f", $0) } ?? "")
        _preparationMinutes = State(initialValue: recipe?.preparationMinutes.map(String.init) ?? "")
        _tags = State(initialValue: recipe?.tags.joined(separator: ", ") ?? "")
    }
    private var servingCount: Double { Double(servings.replacingOccurrences(of: ",", with: ".")) ?? 1 }
    private var explicitWeight: Double? { Double(totalWeight.replacingOccurrences(of: ",", with: ".")).flatMap { $0 > 0 ? $0 : nil } }
    private var preview: Recipe {
        Recipe(
            id: recipe?.id ?? UUID(), remoteID: recipe?.remoteID, name: name,
            recipeDescription: description, ingredients: ingredients, servings: servingCount,
            totalWeightGrams: explicitWeight,
            preparationSteps: steps.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty },
            preparationMinutes: Int(preparationMinutes),
            tags: tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty },
            isFavorite: recipe?.isFavorite ?? false, filters: selectedFilters,
            createdAt: recipe?.createdAt ?? Date(), updatedAt: recipe?.updatedAt ?? Date(),
            syncStatus: recipe?.syncStatus ?? .local, origin: recipe?.origin ?? .personal,
            globalRecordID: recipe?.globalRecordID, globalSubmissionID: recipe?.globalSubmissionID,
            moderationStatus: recipe?.moderationStatus, rejectionReason: recipe?.rejectionReason,
            imageFileName: recipe?.imageFileName, remoteImageFileName: recipe?.remoteImageFileName,
            shareRecordID: recipe?.shareRecordID
        )
    }

    var body: some View {
        NavigationStack { Form {
            Section(t("recipes.photo")) {
                if let photoData, let image = UIImage(data: photoData) {
                    Image(uiImage: image)
                        .resizable().scaledToFill().frame(maxWidth: .infinity).frame(height: 190).clipped()
                        .clipShape(RoundedRectangle(cornerRadius: HyseRadius.control))
                }
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label(photoData == nil ? t("recipes.add_photo") : t("recipes.change_photo"), systemImage: "photo.on.rectangle")
                }
                if photoData != nil {
                    Button(t("recipes.remove_photo"), role: .destructive) {
                        photoData = nil; photoItem = nil; photoChanged = true
                    }
                }
                if photoError { Text(t("recipes.photo_error")).font(.caption).foregroundStyle(HyseColor.danger) }
            }
            Section(t("recipe_editor.name")) {
                TextField(t("recipe_editor.e_g_protein_pancakes"), text: $name)
                    .textInputAutocapitalization(.words)
                    .font(.title3.weight(.semibold))
            }
            Section {
                LabeledContent(t("recipe_editor.servings")) { TextField(t("recipe_editor.count"), text: $servings).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80) }
                LabeledContent(t("recipes.preparation_time")) { HStack { TextField("0", text: $preparationMinutes).keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 70); Text(t("recipes.minutes")).foregroundStyle(.secondary) } }
                LabeledContent(t("recipes.total_weight")) { HStack { TextField(t("recipes.automatic"), text: $totalWeight).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 100); Text("g").foregroundStyle(.secondary) } }
            } header: {
                Text(t("recipe_editor.portions_and_time"))
            } footer: {
                Text(t("recipe_editor.nutrition_values_calculated_per_serving"))
            }
            Section(t("recipe_editor.ingredients")) {
                ForEach($ingredients) { $ingredient in
                    VStack(alignment: .leading, spacing: HyseSpacing.small) {
                        HStack(spacing: HyseSpacing.medium) {
                            Text(ingredient.food.displayName(using: language))
                                .font(.body.weight(.medium))
                                .foregroundStyle(.primary)
                            Spacer(minLength: HyseSpacing.small)
                            TextField(t("recipe_editor.amount"), value: $ingredient.grams, format: .number.precision(.fractionLength(0...2)))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 78)
                                .accessibilityLabel(t("recipe_editor.amount_1", String(describing: ingredient.food.name)))
                            Text(ingredient.unit.rawValue)
                                .foregroundStyle(.secondary)
                                .frame(minWidth: 24, alignment: .leading)
                            Button { ingredientToInspect = ingredient } label: {
                                Image(systemName: "info.circle").font(.caption).foregroundStyle(.secondary)
                            }
                            .accessibilityLabel(t("recipe_editor.nutrition_1", String(describing: ingredient.food.name)))
                        }
                        IngredientNutritionSummary(food: ingredient.food, amount: ingredient.grams, unit: ingredient.unit)
                    }
                    .padding(.vertical, HyseSpacing.xSmall)
                }.onDelete { ingredients.remove(atOffsets: $0) }
                    Button { showingPicker = true } label: {
                        Label(t("recipe_editor.add_food"), systemImage: "plus")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, minHeight: 32)
                    }
                    if ingredients.contains(where: { $0.grams <= 0 }) { Text(t("recipe_editor.every_ingredient_amount_must_greater_than_0")).font(.caption).foregroundStyle(HyseColor.danger) }
            }
            Section(t("recipes.short_description")) {
                TextEditor(text: $description)
                    .frame(minHeight: 85)
                    .overlay(alignment: .topLeading) { if description.isEmpty { Text(t("recipes.description_hint")).foregroundStyle(.tertiary).padding(.top, 8).padding(.leading, 5).allowsHitTesting(false) } }
            }
            Section {
                ForEach($steps) { $step in
                    HStack(alignment: .top, spacing: HyseSpacing.medium) {
                        Text("\((steps.firstIndex(where: { $0.id == step.id }) ?? 0) + 1).")
                            .font(.headline).foregroundStyle(.secondary)
                        TextField(t("recipes.step_hint"), text: $step.text, axis: .vertical)
                            .lineLimit(2...5)
                    }
                    .padding(.vertical, HyseSpacing.small)
                }
                .onDelete { steps.remove(atOffsets: $0) }
                .onMove { steps.move(fromOffsets: $0, toOffset: $1) }
                Button { steps.append(EditableRecipeStep(text: "")) } label: {
                    Label(t("recipes.add_step"), systemImage: "plus")
                }
                if recipe == nil && steps.allSatisfy({ $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                    Text(t("recipes.step_required")).font(.caption).foregroundStyle(HyseColor.danger)
                }
            } header: {
                Text(t("recipes.preparation_steps"))
            } footer: {
                Text(t("recipes.steps_footer"))
            }
            Section(t("recipe_editor.search_properties")) {
                filterPicker(title: t("recipe_editor.diet"), filters: RecipeFilter.dietary)
                filterPicker(title: t("edit_entry.meal"), filters: RecipeFilter.meals)
                TextField(t("recipes.tags_placeholder"), text: $tags)
            }
            Section(t("recipe_editor.summary")) {
                RecipeSummary(preview: preview)
            }
        }.hyseForm().navigationTitle(recipe == nil ? t("recipe_editor.create_recipe") : t("recipe_editor.edit_recipe")).toolbar { ToolbarItem(placement: .cancellationAction) { Button(t("app_tabs.cancel")) { dismiss() } } }
        .safeAreaInset(edge: .bottom) {
            Button(t("recipe_editor.save")) { save() }
                .buttonStyle(HysePrimaryButtonStyle())
                .disabled(!canSave)
                .padding(.horizontal, HyseSpacing.page)
                .padding(.vertical, HyseSpacing.medium)
                .background(HyseColor.background)
        }
        .sheet(isPresented: $showingPicker) {
            AddEntryView(
                foodStore: foodStore,
                recipeStore: recipeStore,
                categoryStore: categoryStore,
                frequencyStore: frequencyStore,
                userSettings: userSettings,
                calorieStore: calorieStore,
                availableCalories: 0,
                category: categoryStore.categories.first ?? MealCategory(name: "", order: 0),
                entryDate: Date(),
                foodSelectionHandler: { food in
                    ingredients.append(RecipeIngredient(food: food, grams: 100))
                }
            )
        }
        .sheet(item: $ingredientToInspect) { FoodNutrientDetail(food: $0.food, amount: $0.grams, unit: $0.unit) }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { @MainActor in
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data),
                      let jpeg = image.hyseCompressedJPEG(maxDimension: 1400, maxBytes: 1_800_000) else {
                    photoError = true; return
                }
                photoData = jpeg; photoChanged = true; photoError = false
            }
        }
        .task(id: recipe?.remoteImageFileName) {
            guard photoData == nil, let recipe, let remoteID = recipe.remoteID,
                  let fileName = recipe.remoteImageFileName, authManager.isLoggedIn else { return }
            if let data = await RecipeSyncService.shared.downloadImage(remoteID: remoteID, fileName: fileName, token: authManager.token) {
                RecipeImageStore.cacheRemote(data, remoteID: remoteID, fileName: fileName)
                if !photoChanged { photoData = data }
            }
        }
        }.hyseScreen()
    }
    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !ingredients.isEmpty && servingCount > 0
        && !ingredients.contains(where: { $0.grams <= 0 })
        && (recipe != nil || steps.contains { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
    }
    private func save() {
        var value = preview
        if photoChanged {
            do { value.imageFileName = try photoData.map(RecipeImageStore.save) }
            catch { photoError = true; return }
        }
        if recipe == nil { recipeStore.add(value) } else { recipeStore.update(value) }
        dismiss()
    }
    private func filterPicker(title: String, filters: [RecipeFilter]) -> some View {
        VStack(alignment: .leading, spacing: HyseSpacing.medium) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 125), spacing: HyseSpacing.small)], spacing: HyseSpacing.small) {
                ForEach(filters) { filter in
                    let selected = selectedFilters.contains(filter)
                    Button {
                        if selected { selectedFilters.remove(filter) } else { selectedFilters.insert(filter) }
                    } label: {
                        HStack(spacing: HyseSpacing.small) {
                            Text(filter.title).lineLimit(1)
                            if selected { Image(systemName: "checkmark").font(.caption2.weight(.bold)) }
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .padding(.horizontal, HyseSpacing.small)
                        .background(Color.primary.opacity(selected ? 0.11 : 0.05), in: Capsule())
                        .overlay(Capsule().stroke(Color.primary.opacity(selected ? 0.26 : 0.08)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
    }
}

private struct IngredientNutritionSummary: View {
    let food: FoodItem
    let amount: Double
    let unit: FoodUnit
    private var nutrients: CalculatedNutrients { food.calculatedValues(forGrams: amount) }

    var body: some View {
        HStack(spacing: HyseSpacing.medium) {
            Text("\(Int(nutrients.kcal)) kcal")
                .foregroundStyle(.primary)
                .fontWeight(.semibold)
            Text(String(format: "P %.1f", nutrients.protein))
            Text(String(format: "C %.1f", nutrients.carbs))
            Text(String(format: "F %.1f", nutrients.fat))
        }
        .font(.caption2.monospacedDigit())
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}

struct FoodNutrientDetail: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var language: LanguageStore
    let food: FoodItem
    let amount: Double
    let unit: FoodUnit
    private var nutrients: CalculatedNutrients { food.calculatedValues(forGrams: amount) }
    var body: some View {
        NavigationStack {
            ScrollView {
                HyseCard {
                    NutrientOverview(nutrients: nutrients, amountLabel: "\(String(format: "%.0f", amount)) \(unit.rawValue)", kcalColor: .primary)
                }
                .padding(HyseSpacing.page)
            }
            .background(HyseNutritionBackdrop())
            .navigationTitle(food.displayName(using: language))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("add_entry.done") { dismiss() } } }
        }
    }
}
struct NutrientOverview: View {
    @EnvironmentObject private var language: LanguageStore
    let nutrients: CalculatedNutrients
    let amountLabel: String
    var kcalColor: Color = HyseColor.accent
    private func t(_ key: String, _ arguments: CVarArg...) -> String { language.text(key, arguments) }
    var body: some View { VStack(spacing: 16) {
        VStack(spacing: 3) { Text("\(t("recipe_editor.nutrition")) \(amountLabel)").font(.caption).foregroundStyle(.secondary); Text("\(Int(nutrients.kcal)) kcal").font(.system(size: 32, weight: .bold, design: .rounded)).foregroundStyle(kcalColor) }
        Grid(horizontalSpacing: 16, verticalSpacing: 10) { GridRow { macro(t("quick_entry.protein"), nutrients.protein, "figure.strengthtraining.traditional"); macro(t("quick_entry.carbohydrates"), nutrients.carbs, "leaf") }; GridRow { macro(t("quick_entry.fat"), nutrients.fat, "drop.fill"); macro(t("quick_entry.sugar"), nutrients.sugar, "cube") } }
        Divider(); Grid(horizontalSpacing: 16, verticalSpacing: 8) { GridRow { LabeledContent(t("quick_entry.fibre")) { Text("\(nutrients.fiber, specifier: "%.1f") g") }; LabeledContent(t("quick_entry.salt")) { Text("\(nutrients.salt, specifier: "%.1f") g") } }; GridRow { LabeledContent(t("quick_entry.saturated_fat")) { Text("\(nutrients.saturatedFat, specifier: "%.1f") g") }; Text("") } }
    }.padding(.vertical, 6) }
    private func macro(_ name: String, _ value: Double, _ symbol: String) -> some View { VStack(alignment: .leading, spacing: 3) { Label(name, systemImage: symbol).font(.caption).foregroundStyle(.secondary); Text("\(value, specifier: "%.1f") g").font(.headline).monospacedDigit() }.frame(maxWidth: .infinity, alignment: .leading) }
}

private struct FoodPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var language: LanguageStore
    @ObservedObject var foodStore: FoodStore
    var onPick: (FoodItem) -> Void
    @State private var search = ""
    @State private var showingScanner = false
    @State private var showingCreateFood = false
    @State private var showingCameraExplanation = false
    @State private var showingCameraDenied = false
    @State private var showingManualBarcode = false
    @State private var manualBarcode = ""
    @State private var scannerTorchOn = false
    @State private var scannerCreationReady = false
    @State private var scannedBarcode = ""
    @State private var externalDraft: FoodItem?
    @State private var initialFoodName = ""
    @State private var isLookingUpBarcode = false
    @State private var alertMessage: String?
    private var results: [FoodItem] { foodStore.searchFoods(query: search) }

    var body: some View {
        NavigationStack {
            ZStack {
                List {
                    Section {
                        HStack(spacing: HyseSpacing.medium) {
                            HyseSearchField(placeholder: language.text("add_entry.search_food"), text: $search)
                            Button { beginBarcodeScan() } label: {
                                Image(systemName: "barcode.viewfinder")
                            }
                            .buttonStyle(HyseIconButtonStyle())
                            .accessibilityLabel(language.text("barcode.search_existing"))
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    if results.isEmpty && !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Section {
                            HyseEmptyState(
                                icon: "fork.knife.circle",
                                title: language.text("add_entry.no_food_found"),
                                message: language.text("add_entry.create_food_from_search"),
                                actionTitle: language.text("ui.create_new_food"),
                                action: createFoodFromSearch
                            )
                        }
                    } else {
                        Section {
                            ForEach(results) { food in
                                Button { onPick(food); dismiss() } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(food.displayName(using: language)).foregroundStyle(.primary)
                                        HStack(spacing: 7) {
                                            foodValue("\(Int(food.kcalPerNutritionReference)) kcal", .secondary)
                                            foodValue(String(format: "P %.1f g", food.proteinPerNutritionReference), .secondary)
                                            foodValue(String(format: "F %.1f g", food.fatPerNutritionReference), .secondary)
                                            foodValue(String(format: "C %.1f g", food.carbsPerNutritionReference), .secondary)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .hyseForm()
                if isLookingUpBarcode {
                    Color.black.opacity(0.25).ignoresSafeArea()
                    ProgressView(language.text("barcode.checking_hyse"))
                        .padding().background(HyseColor.surface, in: RoundedRectangle(cornerRadius: HyseRadius.card))
                        .overlay(RoundedRectangle(cornerRadius: HyseRadius.card).stroke(HyseColor.border))
                }
            }
            .navigationTitle("ui.choose_food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("app_tabs.cancel") { dismiss() } } }
            .sheet(isPresented: $showingCreateFood) {
                CreateFoodView(foodStore: foodStore, barcode: scannedBarcode, draft: externalDraft, initialName: initialFoodName) { food in
                    onPick(food)
                    dismiss()
                }
            }
            .sheet(isPresented: $showingScanner) { scannerSheet }
            .alert(language.text("barcode.camera_permission_title"), isPresented: $showingCameraExplanation) {
                Button(language.text("app_tabs.cancel"), role: .cancel) {}
                Button(language.text("barcode.allow_camera")) { requestCameraAccess() }
            } message: { Text(language.text("barcode.camera_permission_explanation")) }
            .alert(language.text("barcode.camera_permission_denied_title"), isPresented: $showingCameraDenied) {
                Button(language.text("app_tabs.cancel"), role: .cancel) {}
                Button(language.text("barcode.open_settings")) {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                Button(language.text("barcode.enter_manually")) { showingManualBarcode = true }
            } message: { Text(language.text("barcode.camera_permission_denied_message")) }
            .alert(language.text("barcode.manual_title"), isPresented: $showingManualBarcode) {
                TextField(language.text("barcode.manual_placeholder"), text: $manualBarcode).keyboardType(.numberPad)
                Button(language.text("app_tabs.cancel"), role: .cancel) { manualBarcode = "" }
                Button(language.text("barcode.lookup")) {
                    let value = manualBarcode
                    manualBarcode = ""
                    lookupBarcode(value)
                }
            } message: { Text(language.text("barcode.manual_explanation")) }
            .alert("ui.notice", isPresented: Binding(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } })) {
                Button("common.ok") { alertMessage = nil }
            } message: { Text(alertMessage ?? "") }
        }
        .task(id: search) { await foodStore.hydrateGlobalSearch(for: search) }
    }

    @ViewBuilder private var scannerSheet: some View {
        if scannerCreationReady {
            CreateFoodView(foodStore: foodStore, barcode: scannedBarcode, draft: externalDraft) { food in
                onPick(food)
                scannerCreationReady = false
                showingScanner = false
                dismiss()
            }
        } else {
            NavigationStack {
                Group {
                    if isLookingUpBarcode {
                        VStack(spacing: HyseSpacing.medium) {
                            ProgressView().controlSize(.large)
                            Text(language.text("barcode.searching_external")).font(.headline)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(HyseColor.background)
                    } else {
                        BarcodeScannerView(
                            torchOn: $scannerTorchOn,
                            onScanned: lookupBarcode,
                            onError: { error in showingScanner = false; alertMessage = error }
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.white, lineWidth: 3)
                                .frame(width: 280, height: 170).shadow(color: .black.opacity(0.55), radius: 5)
                        }
                        .safeAreaInset(edge: .bottom) {
                            HStack(spacing: 24) {
                                Button { scannerTorchOn.toggle() } label: {
                                    Label(language.text("barcode.flashlight"), systemImage: scannerTorchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                                }
                                Button { showingScanner = false; showingManualBarcode = true } label: {
                                    Label(language.text("barcode.enter_manually"), systemImage: "keyboard")
                                }
                            }
                            .buttonStyle(.borderedProminent).padding().frame(maxWidth: .infinity).background(HyseColor.background)
                        }
                    }
                }
                .navigationTitle(isLookingUpBarcode ? "ui.create_food" : "ui.scan_barcode")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { if !isLookingUpBarcode { Button("app_tabs.cancel") { showingScanner = false } } } }
            }
            .interactiveDismissDisabled(isLookingUpBarcode)
        }
    }

    private func createFoodFromSearch() {
        initialFoodName = search.trimmingCharacters(in: .whitespacesAndNewlines)
        scannedBarcode = ""
        externalDraft = nil
        showingCreateFood = true
    }

    private func beginBarcodeScan() {
        scannerTorchOn = false
        scannerCreationReady = false
        isLookingUpBarcode = false
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: showingScanner = true
        case .notDetermined: showingCameraExplanation = true
        case .denied, .restricted: showingCameraDenied = true
        @unknown default: showingCameraDenied = true
        }
    }

    private func requestCameraAccess() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                if granted { showingScanner = true }
                else { showingCameraDenied = true }
            }
        }
    }

    private func lookupBarcode(_ code: String) {
        let normalized: String
        do { normalized = try BarcodeNormalizer.normalize(code) }
        catch { alertMessage = error.localizedDescription; return }
        isLookingUpBarcode = true
        Task {
            let externalTask = Task { try? await OpenFoodFactsService.shared.fetchProduct(barcode: normalized) }
            let matches = await foodStore.lookupKnownBarcode(normalized)
            if matches.count == 1, let food = matches.first {
                externalTask.cancel()
                isLookingUpBarcode = false
                showingScanner = false
                onPick(food)
                dismiss()
                return
            }
            if matches.count > 1 {
                externalTask.cancel()
                isLookingUpBarcode = false
                showingScanner = false
                alertMessage = language.text("barcode.conflicting_matches")
                return
            }
            let fetched = await externalTask.value
            isLookingUpBarcode = false
            scannedBarcode = normalized
            externalDraft = fetched
            initialFoodName = ""
            if showingScanner { scannerCreationReady = true }
            else { showingCreateFood = true }
        }
    }

    private func foodValue(_ text: String, _ color: Color) -> some View {
        Text(text).font(.caption.monospacedDigit()).foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(color.opacity(0.10), in: Capsule())
    }
}

private struct RecipeSummary: View {
    @EnvironmentObject private var language: LanguageStore
    let preview: Recipe

    var body: some View {
        VStack(alignment: .leading, spacing: HyseSpacing.large) {
            NutrientOverview(nutrients: preview.nutrientsPerServing, amountLabel: language.text("recipe_editor.one_serving"), kcalColor: .primary)
            DisclosureGroup(language.text("recipe_editor.more_nutrition")) {
                VStack(alignment: .leading, spacing: HyseSpacing.large) {
                    NutrientOverview(nutrients: preview.totalNutrients, amountLabel: language.text("recipe_editor.whole_recipe"), kcalColor: .primary)
                    if preview.hasReliableTotalWeight {
                        NutrientOverview(nutrients: preview.nutrientsPer100g, amountLabel: language.text("recipes.per_100_g"), kcalColor: .primary)
                    } else {
                        Label(language.text("recipes.weight_conversion_unavailable"), systemImage: "info.circle")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.top, HyseSpacing.medium)
            }
            .font(.subheadline.weight(.medium))
        }
        .padding(.vertical, 4)
    }
}
