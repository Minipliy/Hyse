import SwiftUI

struct EditFoodView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var language: LanguageStore
    @ObservedObject var foodStore: FoodStore
    var foodItem: FoodItem
    var onDeleted: (() -> Void)?

    @State private var name: String
    @State private var brand: String
    @State private var brandRecordID: String?
    @State private var unit: FoodUnit
    @State private var kcalText: String
    @State private var carbsText: String
    @State private var proteinText: String
    @State private var fatText: String
    @State private var sugarText: String
    @State private var fiberText: String
    @State private var saturatedFatText: String
    @State private var saltText: String
    @State private var micronutrients: MicronutrientProfile?
    @State private var barcode: String
    @State private var isFruit: Bool
    @State private var portions: [FoodPortion]

    @State private var showingDeleteAlert = false
    @State private var alertMessage: String?
    private func t(_ key: String, _ arguments: CVarArg...) -> String { language.text(key, arguments) }

    init(foodStore: FoodStore, foodItem: FoodItem, onDeleted: (() -> Void)? = nil) {
        self.foodStore = foodStore
        self.foodItem = foodItem
        self.onDeleted = onDeleted
        _name = State(initialValue: foodItem.name)
        _brand = State(initialValue: foodItem.brand ?? "")
        _brandRecordID = State(initialValue: foodItem.brandRecordID)
        _unit = State(initialValue: foodItem.unit)
        _kcalText = State(initialValue: EditFoodView.nutrientText(foodItem.unit.displayedNutrientValue(fromPer100: foodItem.kcalPer100g)))
        _carbsText = State(initialValue: EditFoodView.optionalNutrientText(foodItem.unit.displayedNutrientValue(fromPer100: foodItem.carbsPer100g)))
        _proteinText = State(initialValue: EditFoodView.optionalNutrientText(foodItem.unit.displayedNutrientValue(fromPer100: foodItem.proteinPer100g)))
        _fatText = State(initialValue: EditFoodView.optionalNutrientText(foodItem.unit.displayedNutrientValue(fromPer100: foodItem.fatPer100g)))
        _sugarText = State(initialValue: EditFoodView.optionalNutrientText(foodItem.unit.displayedNutrientValue(fromPer100: foodItem.sugarPer100g)))
        _fiberText = State(initialValue: EditFoodView.optionalNutrientText(foodItem.unit.displayedNutrientValue(fromPer100: foodItem.fiberPer100g)))
        _saturatedFatText = State(initialValue: EditFoodView.optionalNutrientText(foodItem.unit.displayedNutrientValue(fromPer100: foodItem.saturatedFatPer100g)))
        _saltText = State(initialValue: EditFoodView.optionalNutrientText(foodItem.unit.displayedNutrientValue(fromPer100: foodItem.saltPer100g)))
        _micronutrients = State(initialValue: foodItem.micronutrients)
        _barcode = State(initialValue: foodItem.barcode ?? "")
        _isFruit = State(initialValue: foodItem.isFruit)
        _portions = State(initialValue: foodItem.portions)
    }

    private static func nutrientText(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }

    private static func optionalNutrientText(_ value: Double) -> String {
        value == 0 ? "" : nutrientText(value)
    }

    private func parseDouble(_ text: String) -> Double? {
        let cleaned = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        return Double(cleaned)
    }

    private var isValid: Bool {
        let nameValid = !name.trimmingCharacters(in: .whitespaces).isEmpty
        let kcalValid = parseDouble(kcalText) != nil
        return nameValid && kcalValid
    }

    private var serving: Double? { portions.first(where: \.isDefault)?.baseAmount(in: unit) }
    private var previewAmount: Double { serving ?? unit.nutritionReferenceAmount }
    private var previewKcal: Double { (parseDouble(kcalText) ?? 0) * previewAmount / unit.nutritionReferenceAmount }
    private var previewFactor: Double { previewAmount / unit.nutritionReferenceAmount }

    var body: some View {
        NavigationStack {
            Form {
                editorHero
                    .listRowInsets(EdgeInsets(top: HyseSpacing.small, leading: HyseSpacing.page, bottom: HyseSpacing.small, trailing: HyseSpacing.page))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                moderationSection
                sourceAttributionSection
                basicInformationSection
                nutritionInputSections
                Section {
                    MicronutrientEditorButton(food: micronutrientDraft, amount: unit.nutritionReferenceAmount, profile: $micronutrients)
                }
                portionsAndBarcodeSections
                previewSectionIfValid
                deleteSection
            }
            .hyseForm()
            .navigationTitle("ui.edit_food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("app_tabs.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("recipe_editor.save") {
                        saveChanges()
                    }
                    .disabled(!isValid)
                }
            }
            .alert("ui.delete_food", isPresented: $showingDeleteAlert) {
                Button("app_tabs.cancel", role: .cancel) { }
                Button("settings.delete", role: .destructive) {
                    foodStore.deleteFood(id: foodItem.id)
                    onDeleted?()
                    dismiss()
                }
            } message: {
                Text("ui.do_you_really_want_delete_food_existing")
            }
            .alert("ui.notice", isPresented: Binding(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } })) {
                Button("common.ok") { alertMessage = nil }
            } message: { Text(alertMessage ?? "") }
        }
        .hyseScreen()
        .onChange(of: unit) { oldUnit, newUnit in
            convertNutrientInputs(from: oldUnit, to: newUnit)
            micronutrients = micronutrients?.converted(from: oldUnit, to: newUnit)
        }
        .onChange(of: foodStore.food(id: foodItem.id)?.micronutrients) { _, refreshed in
            guard let refreshed else { return }
            if micronutrients == nil || (micronutrients?.source == .database && micronutrients?.sourceName == "Open Food Facts") {
                micronutrients = refreshed.converted(from: foodItem.unit, to: unit)
            }
        }
    }

    private func saveChanges() {
        var updated = foodItem
        updated.name = name.trimmingCharacters(in: .whitespaces)
        updated.brand = brand.trimmingCharacters(in: .whitespaces).isEmpty ? nil : brand.trimmingCharacters(in: .whitespaces)
        updated.brandRecordID = brandRecordID
        updated.unit = unit
        updated.kcalPer100g = storedNutrient(kcalText)
        updated.carbsPer100g = storedNutrient(carbsText)
        updated.proteinPer100g = storedNutrient(proteinText)
        updated.fatPer100g = storedNutrient(fatText)
        updated.sugarPer100g = storedNutrient(sugarText)
        updated.fiberPer100g = storedNutrient(fiberText)
        updated.saturatedFatPer100g = storedNutrient(saturatedFatText)
        updated.saltPer100g = storedNutrient(saltText)
        let latest = foodStore.food(id: foodItem.id)?.micronutrients?.converted(from: foodItem.unit, to: unit)
        updated.micronutrients = latest.map { micronutrients?.addingOpenFoodFacts($0) ?? $0 } ?? micronutrients
        updated.isFruit = isFruit
        updated.portions = portions.normalized(defaultUnit: unit)
        updated.servingSizeAmount = updated.defaultPortionBaseAmount

        let rawBarcode = barcode.trimmingCharacters(in: .whitespacesAndNewlines)
        if rawBarcode.isEmpty { updated.barcode = nil }
        else {
            do { updated.barcode = try BarcodeNormalizer.normalize(rawBarcode) }
            catch { alertMessage = error.localizedDescription; return }
        }

        foodStore.updateFood(updated)
        dismiss()
    }

    private var micronutrientDraft: FoodItem {
        var draft = foodItem
        draft.name = name
        draft.brand = brand
        draft.unit = unit
        draft.kcalPer100g = storedNutrient(kcalText)
        draft.carbsPer100g = storedNutrient(carbsText)
        draft.proteinPer100g = storedNutrient(proteinText)
        draft.fatPer100g = storedNutrient(fatText)
        draft.barcode = BarcodeNormalizer.normalizedIfValid(barcode)
        draft.micronutrients = micronutrients
        return draft
    }

    private func nutrientField(_ title: String, unit: String, text: Binding<String>, prominent: Bool = false) -> some View {
        LabeledContent(t(title)) {
            HStack(spacing: 5) {
                TextField("0", text: text).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 88)
                    .font(prominent ? .headline.monospacedDigit() : .body.monospacedDigit())
                Text(unit).foregroundStyle(.secondary)
            }
        }
    }

    private var basicInformationSection: some View {
        Section(
            content: {
                TextField("ui.food_name", text: $name)
                    .textInputAutocapitalization(.words)
                BrandPickerButton(foodStore: foodStore, brandName: $brand, brandRecordID: $brandRecordID)
                Picker("ui.unit", selection: $unit) {
                    ForEach(FoodUnit.allCases, id: \.self) { value in
                        Text(t(value.localizationKey)).tag(value)
                    }
                }
            },
            header: {
                Text(t("create_food.basics"))
            },
            footer: {
                Text(t("create_food.nutrition_values_reference", Self.nutrientText(unit.nutritionReferenceAmount), unit.rawValue))
            }
        )
    }

    private var editorHero: some View {
        HyseEditorHero(
            icon: "pencil",
            title: t("ui.edit_food"),
            headline: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? t("ui.food_name")
                : name.trimmingCharacters(in: .whitespacesAndNewlines),
            detail: editorHeroDetail
        )
    }

    private var editorHeroDetail: String {
        guard isValid else {
            return t("create_food.nutrition_values_reference", Self.nutrientText(unit.nutritionReferenceAmount), unit.rawValue)
        }
        return String(
            format: "%d kcal · P %.1f g · %@",
            Int(previewKcal),
            (parseDouble(proteinText) ?? 0) * previewFactor,
            unit.nutritionReferenceLabel
        )
    }

    @ViewBuilder
    private var moderationSection: some View {
        if let status = foodItem.globalModerationStatus {
            Section(
                content: {
                    HStack(alignment: .top, spacing: HyseSpacing.small) {
                        Image(systemName: moderationIcon(status))
                            .foregroundStyle(moderationColor(status))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(moderationMessage(status))
                                .font(.footnote)
                            if let rejectionReason {
                                Text(rejectionReason)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            )
        }
    }

    @ViewBuilder
    private var sourceAttributionSection: some View {
        if let source = foodItem.externalSource, !source.isEmpty {
            Section(content: {
                Label(t("barcode.source_attribution", source), systemImage: "info.circle")
                Text("barcode.external_quality_notice")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            })
        }
    }

    private var rejectionReason: String? {
        guard foodItem.globalModerationStatus == .rejected,
              let reason = foodItem.globalRejectionReason?.trimmingCharacters(in: .whitespacesAndNewlines),
              !reason.isEmpty else {
            return nil
        }
        return reason
    }

    private var nutritionPreviewSection: some View {
        Section(
            content: {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(previewTitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(Int(previewKcal)) kcal")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(HyseColor.accent)
                    }
                    Spacer()
                    Text(previewMacros)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            },
            header: {
                Text("ui.preview")
            }
        )
    }

    private var nutritionInputSections: some View {
        Group {
            Section(
                content: {
                    nutrientField("quick_entry.calories", unit: "kcal", text: $kcalText, prominent: true)
                },
                header: {
                    Text("ui.energy")
                }
            )

            Section(
                content: {
                    nutrientField("quick_entry.carbohydrates", unit: "g", text: $carbsText)
                    nutrientField("quick_entry.protein", unit: "g", text: $proteinText)
                    nutrientField("quick_entry.fat", unit: "g", text: $fatText)
                },
                header: {
                    Text("ui.macronutrients")
                }
            )

            Section(
                content: {
                    nutrientField("quick_entry.sugar", unit: "g", text: $sugarText)
                    nutrientField("quick_entry.fibre", unit: "g", text: $fiberText)
                    nutrientField("quick_entry.saturated_fat", unit: "g", text: $saturatedFatText)
                    nutrientField("quick_entry.salt", unit: "g", text: $saltText)
                    Toggle("ui.classify_as_fruit", isOn: $isFruit)
                },
                header: {
                    Text("ui.additional_nutrition")
                },
                footer: {
                    Text("ui.foods_marked_as_fruit_sugar_counted_as")
                }
            )
        }
    }

    private var portionsAndBarcodeSections: some View {
        Group {
            FoodPortionsEditor(portions: $portions, baseUnit: unit)
            Section(
                content: {
                    BarcodeInputField(barcode: $barcode)
                },
                header: {
                    Text("ui.serving_barcode")
                }
            )
        }
    }

    @ViewBuilder
    private var previewSectionIfValid: some View {
        if isValid {
            nutritionPreviewSection
        }
    }

    private var deleteSection: some View {
        Section(content: {
            Button("ui.delete_food", role: .destructive) {
                showingDeleteAlert = true
            }
        })
    }

    private var previewTitle: String {
        serving == nil
            ? language.text("create_food.per_reference_unit", [Self.nutrientText(unit.nutritionReferenceAmount), unit.rawValue])
            : language.text("create_food.per_serving")
    }

    private var previewMacros: String {
        String(
            format: "P %.1f · F %.1f · C %.1f g",
            (parseDouble(proteinText) ?? 0) * previewFactor,
            (parseDouble(fatText) ?? 0) * previewFactor,
            (parseDouble(carbsText) ?? 0) * previewFactor
        )
    }

    private func storedNutrient(_ text: String) -> Double {
        unit.per100NutrientValue(fromDisplayed: parseDouble(text) ?? 0)
    }

    private func convertNutrientInputs(from oldUnit: FoodUnit, to newUnit: FoodUnit) {
        kcalText = convertedNutrientText(kcalText, from: oldUnit, to: newUnit)
        carbsText = convertedNutrientText(carbsText, from: oldUnit, to: newUnit)
        proteinText = convertedNutrientText(proteinText, from: oldUnit, to: newUnit)
        fatText = convertedNutrientText(fatText, from: oldUnit, to: newUnit)
        sugarText = convertedNutrientText(sugarText, from: oldUnit, to: newUnit)
        fiberText = convertedNutrientText(fiberText, from: oldUnit, to: newUnit)
        saturatedFatText = convertedNutrientText(saturatedFatText, from: oldUnit, to: newUnit)
        saltText = convertedNutrientText(saltText, from: oldUnit, to: newUnit)
    }

    private func convertedNutrientText(_ text: String, from oldUnit: FoodUnit, to newUnit: FoodUnit) -> String {
        guard let value = parseDouble(text) else { return text }
        return Self.nutrientText(oldUnit.convertedNutrientDisplayValue(value, to: newUnit))
    }

    private func moderationMessage(_ status: GlobalModerationStatus) -> String {
        switch status {
        case .approved:
            return language.text("edit_food.available_globally_changes_reviewed_again_as_new")
        case .pending:
            return language.text("edit_food.changes_being_reviewed_version_visible_only_you")
        case .rejected:
            return language.text("edit_food.change_was_rejected_previous_global_version_remains")
        }
    }

    private func moderationIcon(_ status: GlobalModerationStatus) -> String {
        switch status {
        case .approved: "checkmark.seal.fill"
        case .pending: "clock"
        case .rejected: "xmark.circle"
        }
    }

    private func moderationColor(_ status: GlobalModerationStatus) -> Color {
        switch status {
        case .approved: HyseColor.success
        case .pending: HyseColor.warning
        case .rejected: HyseColor.danger
        }
    }
}
