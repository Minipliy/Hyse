import SwiftUI

struct CreateFoodView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var language: LanguageStore
    private func t(_ key: String, _ arguments: CVarArg...) -> String { language.text(key, arguments) }
    @ObservedObject var foodStore: FoodStore
    @State private var name = ""
    @State private var brand = ""
    @State private var brandRecordID: String?
    @State private var unit: FoodUnit = .gram
    @State private var kcalText = ""
    @State private var carbsText = ""
    @State private var proteinText = ""
    @State private var fatText = ""
    @State private var sugarText = ""
    @State private var fiberText = ""
    @State private var saturatedFatText = ""
    @State private var saltText = ""
    @State private var micronutrients: MicronutrientProfile?
    @State private var isFruit = false
    @State private var portions: [FoodPortion] = []
    @State var barcode: String = ""
    @State private var isSaving = false
    @State private var validationMessage: String?
    private let externalSource: String?
    private let externalSourceID: String?
    private let externalFetchedAt: Date?
    var onSaved: ((FoodItem) -> Void)?

    init(foodStore: FoodStore, barcode: String = "", draft: FoodItem? = nil, initialName: String = "", onSaved: ((FoodItem) -> Void)? = nil) {
        self.foodStore = foodStore
        self.onSaved = onSaved
        externalSource = draft?.externalSource
        externalSourceID = draft?.externalSourceID
        externalFetchedAt = draft?.externalFetchedAt
        _name = State(initialValue: draft?.name ?? initialName)
        _brand = State(initialValue: draft?.brand ?? "")
        let preferredUnit = FoodUnit(rawValue: UserDefaults.standard.string(forKey: "defaultFoodUnit_v1") ?? "") ?? .gram
        _unit = State(initialValue: draft?.unit ?? preferredUnit)
        _kcalText = State(initialValue: draft.map { Self.nutrientText($0.unit.displayedNutrientValue(fromPer100: $0.kcalPer100g)) } ?? "")
        _carbsText = State(initialValue: draft.map { Self.optionalNutrientText($0.unit.displayedNutrientValue(fromPer100: $0.carbsPer100g)) } ?? "")
        _proteinText = State(initialValue: draft.map { Self.optionalNutrientText($0.unit.displayedNutrientValue(fromPer100: $0.proteinPer100g)) } ?? "")
        _fatText = State(initialValue: draft.map { Self.optionalNutrientText($0.unit.displayedNutrientValue(fromPer100: $0.fatPer100g)) } ?? "")
        _sugarText = State(initialValue: draft.map { Self.optionalNutrientText($0.unit.displayedNutrientValue(fromPer100: $0.sugarPer100g)) } ?? "")
        _fiberText = State(initialValue: draft.map { Self.optionalNutrientText($0.unit.displayedNutrientValue(fromPer100: $0.fiberPer100g)) } ?? "")
        _saturatedFatText = State(initialValue: draft.map { Self.optionalNutrientText($0.unit.displayedNutrientValue(fromPer100: $0.saturatedFatPer100g)) } ?? "")
        _saltText = State(initialValue: draft.map { Self.optionalNutrientText($0.unit.displayedNutrientValue(fromPer100: $0.saltPer100g)) } ?? "")
        _micronutrients = State(initialValue: draft?.micronutrients)
        _portions = State(initialValue: draft?.portions ?? [])
        _isFruit = State(initialValue: draft?.isFruit ?? false)
        _barcode = State(initialValue: draft?.barcode ?? barcode)
    }

    private func number(_ text: String) -> Double? { Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")) }
    private var isValid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && number(kcalText) != nil }
    private var serving: Double? { portions.first(where: \.isDefault)?.baseAmount(in: unit) }
    private var previewAmount: Double { serving ?? unit.nutritionReferenceAmount }
    private var previewKcal: Double { (number(kcalText) ?? 0) * previewAmount / unit.nutritionReferenceAmount }
    private var previewFactor: Double { previewAmount / unit.nutritionReferenceAmount }

    var body: some View {
        NavigationStack {
            Form {
                editorHero
                    .listRowInsets(EdgeInsets(top: HyseSpacing.small, leading: HyseSpacing.page, bottom: HyseSpacing.small, trailing: HyseSpacing.page))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                if !barcode.isEmpty, externalSource == nil {
                    Section {
                        Label(t("barcode.create_not_found_title"), systemImage: "plus.circle.fill")
                            .font(.headline)
                            .foregroundStyle(HyseColor.accent)
                        Text(t("barcode.create_not_found_message"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                if let externalSource {
                    Section {
                        Label(t("barcode.source_attribution", externalSource), systemImage: "info.circle")
                        Text("barcode.external_quality_notice").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section {
                    TextField("ui.food_name", text: $name)
                        .textInputAutocapitalization(.words)
                    BrandPickerButton(foodStore: foodStore, brandName: $brand, brandRecordID: $brandRecordID)
                    Picker("ui.unit", selection: $unit) {
                        ForEach(FoodUnit.allCases, id: \.self) { value in
                            Text(t(value.localizationKey)).tag(value)
                        }
                    }
                } header: { Text(t("create_food.basics")) } footer: {
                    Text(t("create_food.nutrition_values_reference", Self.nutrientText(unit.nutritionReferenceAmount), unit.rawValue))
                }

                Section("ui.energy") {
                    nutrientField("quick_entry.calories", unit: "kcal", text: $kcalText, prominent: true)
                }

                Section("ui.macronutrients") {
                    nutrientField("quick_entry.carbohydrates", unit: "g", text: $carbsText)
                    nutrientField("quick_entry.protein", unit: "g", text: $proteinText)
                    nutrientField("quick_entry.fat", unit: "g", text: $fatText)
                }

                Section("ui.additional_nutrition") {
                    nutrientField("quick_entry.sugar", unit: "g", text: $sugarText)
                    nutrientField("quick_entry.fibre", unit: "g", text: $fiberText)
                    nutrientField("quick_entry.saturated_fat", unit: "g", text: $saturatedFatText)
                    nutrientField("quick_entry.salt", unit: "g", text: $saltText)
                    Toggle("ui.classify_as_fruit", isOn: $isFruit)
                }

                Section {
                    MicronutrientEditorButton(food: micronutrientDraft, amount: unit.nutritionReferenceAmount, profile: $micronutrients)
                }

                FoodPortionsEditor(portions: $portions, baseUnit: unit)

                Section("ui.serving_barcode") {
                    BarcodeInputField(barcode: $barcode)
                }

                if isValid {
                    Section("ui.preview") {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(serving == nil
                                     ? language.text("create_food.per_reference_unit", [Self.nutrientText(unit.nutritionReferenceAmount), unit.rawValue])
                                     : language.text("create_food.per_serving"))
                                    .font(.caption).foregroundStyle(.secondary)
                                Text("\(Int(previewKcal)) kcal").font(.title3.weight(.bold)).foregroundStyle(HyseColor.accent)
                            }
                            Spacer()
                            Text("P \((number(proteinText) ?? 0) * previewFactor, specifier: "%.1f") · F \((number(fatText) ?? 0) * previewFactor, specifier: "%.1f") · C \((number(carbsText) ?? 0) * previewFactor, specifier: "%.1f") g")
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
                        }
                    }
                }
            }
            .hyseForm()
            .navigationTitle("ui.create_food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("app_tabs.cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button { saveFood() } label: { if isSaving { ProgressView() } else { Text("recipe_editor.save") } }
                        .disabled(!isValid || isSaving)
                }
            }
        }
        .hyseScreen()
        .onChange(of: unit) { oldUnit, newUnit in
            convertNutrientInputs(from: oldUnit, to: newUnit)
            micronutrients = micronutrients?.converted(from: oldUnit, to: newUnit)
        }
        .alert("ui.notice", isPresented: Binding(get: { validationMessage != nil }, set: { if !$0 { validationMessage = nil } })) {
            Button("common.ok") { validationMessage = nil }
        } message: { Text(validationMessage ?? "") }
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

    private var editorHero: some View {
        HyseEditorHero(
            icon: "fork.knife",
            title: t("ui.create_food"),
            headline: name.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? t("ui.food_name"),
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
            (number(proteinText) ?? 0) * previewFactor,
            unit.nutritionReferenceLabel
        )
    }

    private func saveFood() {
        let rawBarcode = barcode.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedBarcode: String?
        if rawBarcode.isEmpty { normalizedBarcode = nil }
        else {
            do { normalizedBarcode = try BarcodeNormalizer.normalize(rawBarcode) }
            catch { validationMessage = error.localizedDescription; return }
        }
        let normalizedPortions = portions.normalized(defaultUnit: unit)
        var item = micronutrientDraft
        item.barcode = normalizedBarcode
        item.servingSizeAmount = normalizedPortions.first(where: \.isDefault)?.baseAmount(in: unit)
        item.portions = normalizedPortions
        isSaving = true
        Task {
            let saved = await foodStore.addFoodResolvingGlobal(item)
            onSaved?(saved)
            isSaving = false
            dismiss()
        }
    }

    private var micronutrientDraft: FoodItem {
        FoodItem(name: name.trimmingCharacters(in: .whitespaces), brand: brand.trimmingCharacters(in: .whitespaces).nilIfEmpty, brandRecordID: brandRecordID, kcalPer100g: storedNutrient(kcalText), carbsPer100g: storedNutrient(carbsText), proteinPer100g: storedNutrient(proteinText), fatPer100g: storedNutrient(fatText), sugarPer100g: storedNutrient(sugarText), fiberPer100g: storedNutrient(fiberText), saturatedFatPer100g: storedNutrient(saturatedFatText), saltPer100g: storedNutrient(saltText), micronutrients: micronutrients, barcode: BarcodeNormalizer.normalizedIfValid(barcode), externalSource: externalSource, externalSourceID: externalSourceID, externalFetchedAt: externalFetchedAt, unit: unit, isFruit: isFruit)
    }

    private func storedNutrient(_ text: String) -> Double {
        unit.per100NutrientValue(fromDisplayed: number(text) ?? 0)
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
        guard let value = number(text) else { return text }
        return Self.nutrientText(oldUnit.convertedNutrientDisplayValue(value, to: newUnit))
    }

    private static func nutrientText(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }

    private static func optionalNutrientText(_ value: Double) -> String {
        value == 0 ? "" : nutrientText(value)
    }
}

private extension String { var nilIfEmpty: String? { isEmpty ? nil : self } }
