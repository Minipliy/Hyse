import SwiftUI

struct BrandPickerButton: View {
    @EnvironmentObject private var language: LanguageStore
    @ObservedObject var foodStore: FoodStore
    @Binding var brandName: String
    @Binding var brandRecordID: String?
    @State private var showingPicker = false

    var body: some View {
        HStack {
            Button { showingPicker = true } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(language.text("food_brand.field")).foregroundStyle(.primary)
                    Text(brandName.isEmpty ? language.text("food_brand.optional_prompt") : brandName)
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if !brandName.isEmpty {
                Button { brandName = ""; brandRecordID = nil } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .accessibilityLabel(language.text("food_brand.clear"))
            }
            Button { showingPicker = true } label: {
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(language.text("food_brand.title"))
        }
        .sheet(isPresented: $showingPicker) {
            BrandSearchView(foodStore: foodStore, initialQuery: brandName) { brand in
                brandName = brand.name
                brandRecordID = brand.id.isEmpty ? nil : brand.id
                BrandRecentCache.remember(brand)
                showingPicker = false
            }
        }
    }
}

private struct BrandSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var language: LanguageStore
    @ObservedObject var foodStore: FoodStore
    @State var query: String
    @State private var results: [FoodBrand] = []
    @State private var isLoading = false
    @State private var selectingBrandID: String?
    @State private var errorMessage: String?
    let onSelect: (FoodBrand) -> Void

    init(foodStore: FoodStore, initialQuery: String, onSelect: @escaping (FoodBrand) -> Void) {
        self.foodStore = foodStore; _query = State(initialValue: initialQuery); _results = State(initialValue: BrandRecentCache.values); self.onSelect = onSelect
    }

    private var cleanQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isSelecting: Bool { selectingBrandID != nil }
    private var hasExactMatch: Bool {
        results.contains { $0.name.compare(cleanQuery, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
    }

    var body: some View {
        NavigationStack {
            List {
                if isLoading { HStack { ProgressView(); Text(language.text("food_brand.searching")) } }
                ForEach(results) { brand in
                    Button { selectBrand(brand) } label: {
                        HStack(spacing: 12) {
                            if selectingBrandID == brand.id {
                                ProgressView()
                            } else {
                                Image(systemName: brand.status == .approved ? "checkmark.seal.fill" : "clock.badge")
                                    .foregroundStyle(brand.status == .approved ? HyseColor.accent : HyseColor.warning)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(brand.name).foregroundStyle(.primary)
                                Text(language.text("food_brand.status.\(brand.status.rawValue)"))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }.disabled(isSelecting)
                }
                if !cleanQuery.isEmpty && !hasExactMatch {
                    Button { createBrand() } label: { Label(language.text("food_brand.create", [cleanQuery]), systemImage: "plus.circle") }
                        .disabled(isLoading || isSelecting)
                }
                if results.isEmpty && !isLoading {
                    ContentUnavailableView(language.text("food_brand.no_results"), systemImage: "tag.slash", description: Text(language.text("food_brand.no_results_help")))
                        .listRowBackground(Color.clear)
                }
                if let errorMessage { Text(errorMessage).font(.caption).foregroundStyle(HyseColor.warning) }
            }
            .searchable(text: $query, prompt: language.text("food_brand.search_prompt"))
            .navigationTitle(language.text("food_brand.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(language.text("app_tabs.cancel")) { dismiss() } } }
            .task(id: query) {
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                await search()
            }
        }
    }

    private func search() async {
        isLoading = true; errorMessage = nil
        do { results = try await foodStore.searchBrands(cleanQuery) }
        catch { results = []; errorMessage = language.text("food_brand.offline_help") }
        isLoading = false
    }

    private func selectBrand(_ brand: FoodBrand) {
        guard !isSelecting else { return }
        guard brand.id.hasPrefix("catalog:") || brand.status != .approved else {
            onSelect(brand)
            return
        }
        selectingBrandID = brand.id; errorMessage = nil
        Task {
            do { onSelect(try await foodStore.createBrand(named: brand.name)) }
            catch {
                if canUseLocalBrand(after: error) {
                    onSelect(FoodBrand(id: "", name: brand.name, normalizedName: brand.normalizedName,
                        slug: brand.slug, aliases: [], status: .pending, createdBy: ""))
                } else { errorMessage = language.text("food_brand.create_failed") }
            }
            selectingBrandID = nil
        }
    }

    private func createBrand() {
        let name = cleanQuery
        guard !name.isEmpty else { return }
        isLoading = true; errorMessage = nil
        Task {
            do { onSelect(try await foodStore.createBrand(named: name)) }
            catch {
                // Guests and offline users may retain a local display snapshot;
                // it is not presented as a globally created brand.
                if canUseLocalBrand(after: error) {
                    onSelect(FoodBrand(id: "", name: name, normalizedName: name.lowercased(), slug: "", aliases: [], status: .pending, createdBy: ""))
                } else { errorMessage = language.text("food_brand.create_failed") }
            }
            isLoading = false
        }
    }

    private func canUseLocalBrand(after error: Error) -> Bool {
        guard let code = (error as? URLError)?.code else { return false }
        let localCodes: Set<URLError.Code> = [.userAuthenticationRequired, .notConnectedToInternet,
            .networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .timedOut]
        return localCodes.contains(code)
    }
}

private enum BrandRecentCache {
    private static let key = "recent_food_brands_v1"
    static var values: [FoodBrand] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([FoodBrand].self, from: data)) ?? []
    }
    static func remember(_ brand: FoodBrand) {
        guard !brand.id.isEmpty else { return }
        var current = values.filter { $0.id != brand.id }
        current.insert(brand, at: 0)
        UserDefaults.standard.set(try? JSONEncoder().encode(Array(current.prefix(8))), forKey: key)
    }
}

struct FoodPortionsEditor: View {
    @EnvironmentObject private var language: LanguageStore
    @Binding var portions: [FoodPortion]
    let baseUnit: FoodUnit

    var body: some View {
        Section {
            ForEach(portions.sorted { $0.sortOrder < $1.sortOrder }) { portion in
                NavigationLink {
                    portionEditor(portion)
                } label: {
                    HStack {
                        Image(systemName: portion.isDefault ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(portion.isDefault ? HyseColor.accent : .secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(portion.displayName(using: language)).foregroundStyle(.primary)
                            Text("\(portion.amount.clean) \(portion.unit.rawValue)").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(language.text("food_portion.status.\(portion.status.rawValue)"))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(portion.status == .approved ? HyseColor.accent : .secondary)
                    }
                }
            }
            .onDelete { offsets in
                let sorted = portions.sorted { $0.sortOrder < $1.sortOrder }
                let ids = Set(offsets.map { sorted[$0].id })
                portions.removeAll { ids.contains($0.id) }
                normalize()
            }
            .onMove { source, destination in
                var sorted = portions.sorted { $0.sortOrder < $1.sortOrder }
                sorted.move(fromOffsets: source, toOffset: destination)
                portions = sorted.enumerated().map { index, source in var value = source; value.sortOrder = index; value.updatedAt = Date(); return value }
            }
            NavigationLink {
                portionEditor(FoodPortion(
                    customName: "",
                    amount: 0,
                    unit: baseUnit,
                    sortOrder: portions.count,
                    isDefault: portions.isEmpty,
                    status: .pending
                ))
            } label: {
                Label(language.text("food_portion.add"), systemImage: "plus.circle")
            }
        } header: { Text(language.text("food_portion.section")) } footer: { Text(language.text("food_portion.explanation")) }
    }

    private func portionEditor(_ portion: FoodPortion) -> some View {
        FoodPortionEditSheet(portion: portion, baseUnit: baseUnit) { updated in
            if let index = portions.firstIndex(where: { $0.id == updated.id }) { portions[index] = updated }
            else { portions.append(updated) }
            if updated.isDefault { for index in portions.indices where portions[index].id != updated.id { portions[index].isDefault = false } }
            normalize()
        }
    }

    private func normalize() { portions = portions.normalized(defaultUnit: baseUnit) }
}

private struct FoodPortionEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var language: LanguageStore
    @EnvironmentObject private var authManager: AuthManager
    @State var portion: FoodPortion
    let baseUnit: FoodUnit
    let onSave: (FoodPortion) -> Void
    @State private var amountText = ""
    @State private var gramsText = ""
    @State private var originalPortion: FoodPortion?

    private var amount: Double? { Double(amountText.replacingOccurrences(of: ",", with: ".")) }
    private var grams: Double? { Double(gramsText.replacingOccurrences(of: ",", with: ".")) }
    private var valid: Bool {
        let hasName = !(portion.nameKey?.isEmpty ?? true) || !portion.customName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasName && (amount ?? 0) > 0 && (!requiresManualConversion || (grams ?? 0) > 0)
    }
    private var requiresManualConversion: Bool {
        guard let amount else { return false }
        return portion.unit != baseUnit && portion.unit.converted(amount, to: baseUnit) == nil
    }

    var body: some View {
        Form {
            TextField(language.text("food_portion.name_prompt"), text: $portion.customName)
            LabeledContent(language.text("food_portion.amount")) { TextField("0", text: $amountText).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
            Picker(language.text("ui.unit"), selection: $portion.unit) {
                ForEach(FoodUnit.allCases, id: \.self) { Text(language.text($0.localizationKey)).tag($0) }
            }
            if requiresManualConversion {
                LabeledContent(language.text("food_portion.gram_equivalent")) { TextField("0", text: $gramsText).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                Text(language.text("food_portion.conversion_warning")).font(.caption).foregroundStyle(HyseColor.warning)
            }
            Toggle(language.text("food_portion.default"), isOn: $portion.isDefault)
            Section {
                if portion.status == .approved {
                    Label(language.text("food_portion.global_approved"), systemImage: "checkmark.seal.fill")
                        .foregroundStyle(HyseColor.accent)
                } else if portion.status == .rejected {
                    Label(language.text("food_portion.global_rejected"), systemImage: "exclamationmark.circle")
                        .font(.caption).foregroundStyle(HyseColor.warning)
                } else {
                    Label(language.text("food_portion.automatic_global"), systemImage: "globe.europe.africa.fill")
                        .foregroundStyle(HyseColor.accent)
                }
            } header: {
                Text(language.text("food_portion.sharing"))
            } footer: {
                Text(language.text(authManager.isLoggedIn ? "food_portion.automatic_global_explanation" : "food_portion.automatic_global_login"))
            }
        }
        .hyseForm()
        .navigationTitle(language.text("food_portion.edit"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(language.text("recipe_editor.save")) { save() }.disabled(!valid)
            }
        }
        .onAppear {
            originalPortion = portion
            amountText = portion.amount > 0 ? portion.amount.clean : ""
            gramsText = portion.gramEquivalent.map(\.clean) ?? ""
        }
    }

    private func save() {
        portion.customName = portion.customName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !portion.customName.isEmpty { portion.nameKey = nil }
        portion.amount = amount ?? 0
        portion.gramEquivalent = requiresManualConversion ? grams : nil
        let approvedContentIsUnchanged = portion.status == .approved
            && originalPortion.map {
                portion.nameKey == $0.nameKey
                    && portion.customName == $0.customName
                    && portion.amount == $0.amount
                    && portion.unit == $0.unit
                    && portion.gramEquivalent == $0.gramEquivalent
                    && portion.isDefault == $0.isDefault
            } == true
        if !approvedContentIsUnchanged {
            // New, edited and previously rejected portions are automatically
            // queued for publication. The local copy remains usable offline.
            portion.status = .pending
        }
        portion.updatedAt = Date()
        onSave(portion)
        dismiss()
    }
}

private extension Double {
    var clean: String { truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", self) : String(format: "%.1f", self) }
}
