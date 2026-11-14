import SwiftUI

extension MicronutrientProfile {
    func converted(from oldUnit: FoodUnit, to newUnit: FoodUnit) -> Self {
        guard oldUnit != newUnit,
              let oldAmountForHundredNew = newUnit.converted(100, to: oldUnit) else { return self }
        return Self(
            valuesPer100g: valuesPer100g.mapValues { $0 * oldAmountForHundredNew / 100 },
            source: source,
            sourceName: sourceName
        )
    }
}

private enum MicronutrientText {
    static func amount(_ value: Double, unit: String) -> String {
        "\(value.formatted(.number.precision(.fractionLength(0...2)).grouping(.never))) \(unit)"
    }

    static func source(_ profile: MicronutrientProfile, language: LanguageStore) -> String {
        switch profile.source {
        case .database: return profile.sourceName ?? language.text("micronutrients.database")
        case .estimated: return language.text("micronutrients.estimate_label")
        case .manual: return language.text("micronutrients.manual")
        case .mixed: return language.text("micronutrients.mixed")
        }
    }
}

struct MicronutrientReadOnlyButton: View {
    @EnvironmentObject private var language: LanguageStore
    @EnvironmentObject private var premium: PremiumAccessStore
    let profile: MicronutrientProfile?
    let amount: Double
    var unit: FoodUnit = .gram
    @State private var showingDetails = false
    @State private var showingPremium = false

    var body: some View {
        Button {
            if premium.hasNutrition { showingDetails = true }
            else { showingPremium = true }
        } label: {
            HStack {
                Label(language.text("micronutrients.title"), systemImage: "leaf")
                Spacer()
                if !premium.hasNutrition { PremiumFeatureIcon(area: .nutrition) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(isPresented: $showingDetails) {
            NavigationStack { MicronutrientDetails(profile: profile, amount: amount, unit: unit) }
        }
        .sheet(isPresented: $showingPremium) { PremiumPaywallView(requestedArea: .nutrition) }
        .onChange(of: premium.hasNutrition) { _, unlocked in
            if !unlocked { showingDetails = false }
        }
    }
}

struct MicronutrientEditorButton: View {
    @EnvironmentObject private var language: LanguageStore
    @EnvironmentObject private var premium: PremiumAccessStore
    let food: FoodItem
    let amount: Double
    @Binding var profile: MicronutrientProfile?
    @State private var showingEditor = false
    @State private var showingPremium = false

    var body: some View {
        Button {
            if premium.hasNutrition { showingEditor = true }
            else { showingPremium = true }
        } label: {
            HStack {
                Label(language.text("micronutrients.title"), systemImage: "leaf")
                Spacer()
                if premium.hasNutrition, let profile, !profile.isEmpty {
                    Text("\(profile.valuesPer100g.count)")
                        .foregroundStyle(.secondary)
                }
                if premium.hasNutrition {
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                } else {
                    PremiumFeatureIcon(area: .nutrition)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(isPresented: $showingEditor) {
            NavigationStack { MicronutrientEditor(food: food, amount: amount, profile: $profile) }
        }
        .sheet(isPresented: $showingPremium) { PremiumPaywallView(requestedArea: .nutrition) }
        .onChange(of: premium.hasNutrition) { _, unlocked in
            if !unlocked { showingEditor = false }
        }
    }
}

private struct MicronutrientDetails: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var language: LanguageStore
    let profile: MicronutrientProfile?
    let amount: Double
    let unit: FoodUnit

    var body: some View {
        List {
            if let profile, !profile.isEmpty {
                Section {
                    ForEach(Micronutrient.allCases, id: \.self) { nutrient in
                        if let value = profile.amount(nutrient, for: amount) {
                            LabeledContent(language.text(nutrient.localizationKey), value: MicronutrientText.amount(value, unit: nutrient.unit))
                        }
                    }
                } header: {
                    Text(language.text("micronutrients.amount_header", ["\(amount.formatted(.number.precision(.fractionLength(0...2)).grouping(.never))) \(unit.rawValue)"]))
                } footer: {
                    Text(MicronutrientText.source(profile, language: language))
                }
            } else {
                Text(language.text("micronutrients.no_data")).foregroundStyle(.secondary)
            }
        }
        .navigationTitle(language.text("micronutrients.title"))
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button(language.text("micronutrients.done")) { dismiss() } } }
    }
}

private struct MicronutrientEditor: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var language: LanguageStore
    @EnvironmentObject private var premium: PremiumAccessStore
    let food: FoodItem
    let amount: Double
    @Binding var profile: MicronutrientProfile?
    @State private var inputs: [String: String] = [:]
    @State private var inputsLoaded = false
    @State private var isEstimating = false
    @State private var estimationFailed = false
    @State private var manuallyChanged = false
    @State private var estimatedProfile: MicronutrientProfile?
    @State private var databaseProfile: MicronutrientProfile?
    @State private var isLoadingDatabase = false
    @State private var databaseFailed = false

    private var referenceAmount: Double { food.unit.nutritionReferenceAmount }
    private var metricUnit: FoodUnit { food.unit.isVolume ? .milliliter : .gram }
    private var metricAmountPerReference: Double { food.unit.converted(referenceAmount, to: metricUnit) ?? referenceAmount }

    private func displayValue(_ storedPer100: Double) -> Double { storedPer100 * referenceAmount / 100 }
    private func displayMetricValue(_ per100Metric: Double) -> Double { per100Metric * metricAmountPerReference / 100 }

    var body: some View {
        Form {
            estimateSection
            Section {
                Text(food.name).font(.headline)
                if let profile, !profile.isEmpty {
                    Label(MicronutrientText.source(profile, language: language), systemImage: profile.source == .estimated ? "sparkles" : "info.circle")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text(language.text("micronutrients.unknown_notice"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                ForEach(Micronutrient.allCases, id: \.self) { nutrient in
                    HStack {
                        Text(language.text(nutrient.localizationKey))
                        Spacer(minLength: 4)
                        TextField("—", text: Binding(
                            get: { inputs[nutrient.rawValue] ?? "" },
                            set: { inputs[nutrient.rawValue] = $0; manuallyChanged = true }
                        ))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 78)
                        Text(nutrient.unit).foregroundStyle(.secondary).frame(width: 30, alignment: .leading)
                    }
                }
            } header: { Text(language.text("micronutrients.per_reference", [referenceAmount.formatted(.number.precision(.fractionLength(0...2)).grouping(.never)), food.unit.rawValue])) }
            if let barcode = food.barcode, !barcode.isEmpty {
                Section {
                    Button {
                        guard premium.hasNutrition else { dismiss(); return }
                        loadDatabase(barcode: barcode)
                    } label: {
                        HStack {
                            Label(language.text("micronutrients.database_action"), systemImage: "square.and.arrow.down")
                            Spacer()
                            if isLoadingDatabase { ProgressView() }
                        }
                    }
                    .disabled(isLoadingDatabase)
                    if databaseFailed { Text(language.text("micronutrients.database_failed")).font(.caption).foregroundStyle(.secondary) }
                }
            }
        }
        .navigationTitle(language.text("micronutrients.title"))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button(language.text("app_tabs.cancel")) { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button(language.text("recipe_editor.save")) { save() }.disabled(!premium.hasNutrition || isEstimating || isLoadingDatabase) }
        }
        .onAppear {
            guard premium.hasNutrition else { dismiss(); return }
            guard !inputsLoaded else { return }
            inputs = profile?.valuesPer100g.mapValues { displayValue($0).formatted(.number.precision(.fractionLength(0...2)).grouping(.never)) } ?? [:]
            inputsLoaded = true
            if let barcode = food.barcode, !barcode.isEmpty { loadDatabase(barcode: barcode) }
        }
        .onChange(of: premium.hasNutrition) { _, unlocked in
            if !unlocked { dismiss() }
        }
    }

    private func loadDatabase(barcode: String) {
        guard premium.hasNutrition, !isLoadingDatabase else { return }
        isLoadingDatabase = true
        databaseFailed = false
        Task {
            let imported = try? await OpenFoodFactsService.shared.fetchProduct(barcode: barcode)
            isLoadingDatabase = false
            guard premium.hasNutrition else { return }
            guard let found = imported?.micronutrients, !found.isEmpty else { databaseFailed = true; return }
            databaseProfile = found
            let replaceImported = !manuallyChanged && profile?.source == .database && profile?.sourceName == "Open Food Facts"
            for (key, value) in found.valuesPer100g where replaceImported || inputs[key, default: ""].isEmpty {
                inputs[key] = displayMetricValue(value).formatted(.number.precision(.fractionLength(0...2)).grouping(.never))
            }
        }
    }

    private var estimateSection: some View {
        Section {
            Button {
                guard premium.hasNutrition, !isEstimating else { return }
                isEstimating = true
                estimationFailed = false
                Task {
                    let estimate = await AppleMicronutrientEstimator.estimate(for: food)
                    isEstimating = false
                    guard premium.hasNutrition else { return }
                    guard let estimate else { estimationFailed = true; return }
                    for (key, value) in estimate.valuesPer100g where inputs[key, default: ""].isEmpty {
                        inputs[key] = displayMetricValue(value).formatted(.number.precision(.fractionLength(0...2)).grouping(.never))
                    }
                    estimatedProfile = estimate
                }
            } label: {
                HStack {
                    Label(language.text("micronutrients.estimate_action"), systemImage: "sparkles")
                    Spacer()
                    if isEstimating { ProgressView() }
                }
            }
            .disabled(isEstimating)
            if estimationFailed {
                Text(language.text("micronutrients.estimate_failed"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } footer: {
            Text(language.text("micronutrients.estimate_notice"))
        }
    }

    private func save() {
        guard premium.hasNutrition else { return }
        var values: [String: Double] = [:]
        for nutrient in Micronutrient.allCases {
            let raw = (inputs[nutrient.rawValue] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty, let value = Double(raw.replacingOccurrences(of: ",", with: ".")),
                  value.isFinite, value >= 0 else { continue }
            let stored = value * 100 / referenceAmount
            guard stored.isFinite, stored <= nutrient.maximumPer100g else { continue }
            values[nutrient.rawValue] = stored
        }
        let source: MicronutrientSource
        if manuallyChanged {
            source = profile?.isEmpty == false || estimatedProfile != nil || databaseProfile != nil ? .mixed : .manual
        } else if databaseProfile != nil {
            source = profile?.isEmpty == false || estimatedProfile != nil ? .mixed : .database
        } else if estimatedProfile != nil {
            source = profile?.isEmpty == false ? .mixed : .estimated
        } else {
            source = profile?.source ?? .manual
        }
        let sourceName = source == .database ? "Open Food Facts" : source == .estimated ? "Apple Intelligence" : profile?.sourceName
        let result = MicronutrientProfile(valuesPer100g: values, source: source, sourceName: sourceName)
        profile = result.isEmpty ? nil : result
        dismiss()
    }
}

struct MicronutrientDailyButton: View {
    @EnvironmentObject private var language: LanguageStore
    @EnvironmentObject private var premium: PremiumAccessStore
    let entries: [CalorieEntry]
    @State private var showingDetails = false
    @State private var showingPremium = false

    var body: some View {
        Button {
            if premium.hasNutrition { showingDetails = true }
            else { showingPremium = true }
        } label: {
            HStack {
                Label(language.text("micronutrients.today"), systemImage: "leaf")
                Spacer()
                if premium.hasNutrition {
                    Image(systemName: "chevron.right").font(.caption)
                } else {
                    PremiumFeatureIcon(area: .nutrition)
                }
            }
        }
        .sheet(isPresented: $showingDetails) {
            NavigationStack {
                List {
                    Section {
                        ForEach(Micronutrient.allCases, id: \.self) { nutrient in
                            let known = entries.compactMap { $0.micronutrientAmount(nutrient) }
                            LabeledContent(language.text(nutrient.localizationKey), value: known.isEmpty ? "—" : MicronutrientText.amount(known.reduce(0, +), unit: nutrient.unit))
                        }
                    } footer: {
                        Text(language.text("micronutrients.coverage", [entries.filter { $0.micronutrients?.isEmpty == false }.count, entries.count]))
                    }
                }
                .navigationTitle(language.text("micronutrients.today"))
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(language.text("micronutrients.done")) { showingDetails = false } } }
            }
        }
        .sheet(isPresented: $showingPremium) { PremiumPaywallView(requestedArea: .nutrition) }
        .onChange(of: premium.hasNutrition) { _, unlocked in
            if !unlocked { showingDetails = false }
        }
    }
}
