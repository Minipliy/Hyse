import SwiftUI
import Combine
import CryptoKit
import OSLog

nonisolated struct DailyFoodSchedule: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var food: FoodItem
    var amount: Double
    var categoryID: UUID
    var categoryName: String
    var portionName: String?
    var portionID: UUID?
    var portionCount: Double?
    var isEnabled: Bool
    var processedDayKeys: Set<String>
    var createdAt: Date
    var updatedAt: Date?

    @MainActor init(
        id: UUID = UUID(),
        food: FoodItem,
        amount: Double,
        category: MealCategory,
        portionName: String? = nil,
        portionID: UUID? = nil,
        portionCount: Double? = nil,
        isEnabled: Bool = true,
        processedDayKeys: Set<String> = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.food = food
        self.amount = amount
        self.categoryID = category.id
        self.categoryName = category.storageKey
        self.portionName = portionName
        self.portionID = portionID
        self.portionCount = portionCount
        self.isEnabled = isEnabled
        self.processedDayKeys = processedDayKeys
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }

    var modificationDate: Date { updatedAt ?? createdAt }
}

@MainActor
final class DailyFoodScheduleStore: ObservableObject {
    @Published private(set) var schedules: [DailyFoodSchedule] = []

    weak var authManager: AuthManager?
    private var scope = "guest"
    private var activeAccountID: String?
    private var profileRevision: UInt = 0
    private var syncTask: Task<Void, Never>?
    private var deferredSyncTask: Task<Void, Never>?
    private var lastSuccessfulSyncAt: Date?
    private let logger = Logger(subsystem: "com.hyse.HyseApp", category: "DailyFoodSync")

    init() {
        load()
    }

    func activate(accountID: String?) {
        let nextScope = accountID.map { "account_\($0)" } ?? "guest"
        guard nextScope != scope else {
            if accountID != nil { syncPendingSchedules() }
            return
        }
        profileRevision &+= 1
        syncTask?.cancel()
        deferredSyncTask?.cancel()
        activeAccountID = accountID
        scope = nextScope
        lastSuccessfulSyncAt = accountID.flatMap { UserDefaults.standard.object(forKey: lastSuccessfulSyncKey($0)) as? Date }
        load()
        if let accountID {
            let migrationKey = "daily_food_schedules_cloud_migration_\(accountID)_v1"
            if !UserDefaults.standard.bool(forKey: migrationKey) {
                storeIDs(Set(schedules.map(\.id)), key: dirtyKey(accountID))
                UserDefaults.standard.set(true, forKey: migrationKey)
            }
            syncPendingSchedules()
        }
    }

    func add(_ schedule: DailyFoodSchedule) {
        schedules.append(schedule)
        markDirty(schedule.id)
        save()
        schedulePendingSync()
    }

    func update(_ schedule: DailyFoodSchedule) {
        guard let index = schedules.firstIndex(where: { $0.id == schedule.id }) else { return }
        var updated = schedule
        updated.createdAt = schedules[index].createdAt
        updated.processedDayKeys = schedules[index].processedDayKeys
        updated.updatedAt = Date()
        schedules[index] = updated
        markDirty(updated.id)
        save()
        schedulePendingSync()
    }

    func delete(id: UUID) {
        schedules.removeAll { $0.id == id }
        markDeleted(id)
        save()
        schedulePendingSync()
    }

    func setEnabled(_ enabled: Bool, id: UUID) {
        guard let index = schedules.firstIndex(where: { $0.id == id }) else { return }
        schedules[index].isEnabled = enabled
        schedules[index].updatedAt = Date()
        markDirty(id)
        save()
        schedulePendingSync()
    }

    func reconcileToday(calorieStore: CalorieStore, categories: [MealCategory], now: Date = Date()) {
        guard !schedules.isEmpty, !categories.isEmpty else { return }
        let calendar = Calendar.autoupdatingCurrent
        let day = calendar.startOfDay(for: now)
        let dayKey = StreakTracker.dayKey(for: day, calendar: calendar)
        var entries: [CalorieEntry] = []
        var scheduleIndexes: [Int] = []
        var didUpdateProcessedDays = false

        for index in schedules.indices where schedules[index].isEnabled && !schedules[index].processedDayKeys.contains(dayKey) {
            let schedule = schedules[index]
            guard schedule.amount.isFinite, schedule.amount > 0,
                  let category = resolvedCategory(for: schedule, categories: categories) else { continue }
            let entryID = Self.entryID(scheduleID: schedule.id, dayKey: dayKey)
            if calorieStore.entries.contains(where: { $0.id == entryID }) {
                schedules[index].processedDayKeys.insert(dayKey)
                schedules[index].updatedAt = now
                markDirty(schedules[index].id)
                didUpdateProcessedDays = true
                continue
            }
            entries.append(makeEntry(from: schedule, category: category, id: entryID, date: now))
            scheduleIndexes.append(index)
        }

        if entries.isEmpty {
            if didUpdateProcessedDays {
                pruneAndSave()
                schedulePendingSync()
            }
            return
        }

        guard calorieStore.addEntries(entries, countsTowardStreak: false, enforceTrackingRules: true) else {
            if didUpdateProcessedDays {
                pruneAndSave()
                schedulePendingSync()
            }
            return
        }
        for index in scheduleIndexes {
            schedules[index].processedDayKeys.insert(dayKey)
            schedules[index].updatedAt = now
            markDirty(schedules[index].id)
        }
        pruneAndSave()
        schedulePendingSync()
    }

    private func makeEntry(from schedule: DailyFoodSchedule, category: MealCategory, id: UUID, date: Date) -> CalorieEntry {
        let food = schedule.food
        return CalorieEntry(
            id: id,
            foodItemId: food.id,
            globalFoodRecordID: food.globalRecordID,
            name: food.name,
            grams: schedule.amount,
            categoryId: category.id,
            categoryName: category.storageKey,
            portionName: nil,
            portionID: nil,
            portionCount: nil,
            unit: food.unit,
            kcalPer100g: food.kcalPer100g,
            carbsPer100g: food.carbsPer100g,
            proteinPer100g: food.proteinPer100g,
            fatPer100g: food.fatPer100g,
            addedSugarPer100g: food.isFruit ? 0 : food.sugarPer100g,
            fruitSugarPer100g: food.isFruit ? food.sugarPer100g : 0,
            fiberPer100g: food.fiberPer100g,
            saturatedFatPer100g: food.saturatedFatPer100g,
            saltPer100g: food.saltPer100g,
            micronutrients: food.micronutrients,
            date: date
        )
    }

    private func resolvedCategory(for schedule: DailyFoodSchedule, categories: [MealCategory]) -> MealCategory? {
        categories.first(where: { $0.id == schedule.categoryID })
            ?? categories.first(where: { $0.storageKey == schedule.categoryName })
            ?? categories.first
    }

    private static func entryID(scheduleID: UUID, dayKey: String) -> UUID {
        let digest = SHA256.hash(data: Data("daily-food|\(scheduleID.uuidString)|\(dayKey)".utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7], bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    private func pruneAndSave() {
        for index in schedules.indices where schedules[index].processedDayKeys.count > 400 {
            schedules[index].processedDayKeys = Set(schedules[index].processedDayKeys.sorted().suffix(400))
            schedules[index].updatedAt = Date()
            markDirty(schedules[index].id)
        }
        save()
    }

    private func storageKey() -> String { "daily_food_schedules_\(scope)_v1" }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey()),
              let decoded = try? JSONDecoder().decode([DailyFoodSchedule].self, from: data) else {
            schedules = []
            return
        }
        let containsLegacyPortions = decoded.contains { $0.portionName != nil || $0.portionID != nil || $0.portionCount != nil }
        schedules = decoded.map { source in
            var value = source
            value.portionName = nil
            value.portionID = nil
            value.portionCount = nil
            return value
        }.sorted { $0.createdAt < $1.createdAt }
        if containsLegacyPortions { save() }
    }

    private func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(schedules), forKey: storageKey())
    }

    func syncPendingSchedules() {
        guard let authManager, authManager.isLoggedIn,
              let accountID = activeAccountID,
              accountID == authManager.accountID,
              !authManager.token.isEmpty else { return }
        deferredSyncTask?.cancel()
        deferredSyncTask = nil
        let token = authManager.token
        let localSnapshot = schedules
        let dirty = storedIDs(dirtyKey(accountID))
        let deleted = storedIDs(deletedKey(accountID))
        if dirty.isEmpty, deleted.isEmpty,
           let lastSuccessfulSyncAt, Date().timeIntervalSince(lastSuccessfulSyncAt) < 3_600 { return }
        let expectedRevision = profileRevision
        syncTask?.cancel()
        syncTask = Task { [weak self] in
            let result = await DailyFoodScheduleSyncService.shared.sync(
                schedules: localSnapshot,
                dirtyIDs: dirty,
                deletedIDs: deleted,
                userID: accountID,
                token: token
            )
            guard !Task.isCancelled, let self else { return }
            guard self.profileRevision == expectedRevision,
                  self.activeAccountID == accountID,
                  self.authManager?.accountID == accountID else { return }
            guard result.didFetch else {
                self.logger.error("Daily-food schedule sync could not reach PocketBase")
                self.scheduleRetry()
                return
            }

            let uploadedSnapshot = Dictionary(uniqueKeysWithValues: localSnapshot.map { ($0.id, $0) })
            let currentSnapshot = Dictionary(uniqueKeysWithValues: self.schedules.map { ($0.id, $0) })
            let confirmedUploads = result.uploadedIDs.filter { currentSnapshot[$0] == uploadedSnapshot[$0] }
            var remainingDirty = self.storedIDs(self.dirtyKey(accountID))
            remainingDirty.subtract(confirmedUploads)
            var remainingDeleted = self.storedIDs(self.deletedKey(accountID))
            remainingDeleted.subtract(result.deletedIDs)
            self.storeIDs(remainingDirty, key: self.dirtyKey(accountID))
            self.storeIDs(remainingDeleted, key: self.deletedKey(accountID))

            var merged = Dictionary(uniqueKeysWithValues: result.schedules.map { ($0.id, $0) })
            for id in remainingDirty where !remainingDeleted.contains(id) {
                if let local = currentSnapshot[id] { merged[id] = local }
            }
            remainingDeleted.forEach { merged.removeValue(forKey: $0) }
            self.schedules = Array(merged.values).sorted { $0.createdAt < $1.createdAt }
            self.save()
            if !remainingDirty.isEmpty || !remainingDeleted.isEmpty {
                self.scheduleRetry()
                return
            }
            let now = Date()
            self.lastSuccessfulSyncAt = now
            UserDefaults.standard.set(now, forKey: self.lastSuccessfulSyncKey(accountID))
        }
    }

    /// Complete queued changes before the login token is cleared. Failed
    /// uploads remain dirty and are retried when this account is activated.
    func flushPendingSchedules() async {
        guard let accountID = activeAccountID,
              !storedIDs(dirtyKey(accountID)).isEmpty || !storedIDs(deletedKey(accountID)).isEmpty else { return }
        syncPendingSchedules()
        await syncTask?.value
    }

    private func schedulePendingSync() {
        guard activeAccountID != nil else { return }
        deferredSyncTask?.cancel()
        deferredSyncTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self else { return }
            self.deferredSyncTask = nil
            self.syncPendingSchedules()
        }
    }

    private func scheduleRetry() {
        deferredSyncTask?.cancel()
        deferredSyncTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled, let self else { return }
            self.deferredSyncTask = nil
            self.syncPendingSchedules()
        }
    }

    private func dirtyKey(_ accountID: String) -> String { "daily_food_schedules_dirty_\(accountID)_v1" }
    private func deletedKey(_ accountID: String) -> String { "daily_food_schedules_deleted_\(accountID)_v1" }
    private func lastSuccessfulSyncKey(_ accountID: String) -> String { "daily_food_schedules_last_sync_\(accountID)_v1" }
    private func storedIDs(_ key: String) -> Set<UUID> {
        Set((UserDefaults.standard.stringArray(forKey: key) ?? []).compactMap(UUID.init(uuidString:)))
    }
    private func storeIDs(_ ids: Set<UUID>, key: String) {
        UserDefaults.standard.set(ids.map(\.uuidString), forKey: key)
    }
    private func markDirty(_ id: UUID) {
        guard let accountID = activeAccountID else { return }
        var dirty = storedIDs(dirtyKey(accountID)); dirty.insert(id); storeIDs(dirty, key: dirtyKey(accountID))
        var deleted = storedIDs(deletedKey(accountID)); deleted.remove(id); storeIDs(deleted, key: deletedKey(accountID))
    }
    private func markDeleted(_ id: UUID) {
        guard let accountID = activeAccountID else { return }
        var dirty = storedIDs(dirtyKey(accountID)); dirty.remove(id); storeIDs(dirty, key: dirtyKey(accountID))
        var deleted = storedIDs(deletedKey(accountID)); deleted.insert(id); storeIDs(deleted, key: deletedKey(accountID))
    }
}

struct DailyFoodAutomationView: View {
    @EnvironmentObject private var language: LanguageStore
    @ObservedObject var store: DailyFoodScheduleStore
    @ObservedObject var foodStore: FoodStore
    @ObservedObject var categoryStore: CategoryStore
    @ObservedObject var calorieStore: CalorieStore
    @ObservedObject var frequencyStore: FrequencyStore
    @ObservedObject var recipeStore: RecipeStore
    @ObservedObject var userSettings: UserSettingsStore
    @State private var showingFoodSearch = false
    @State private var selectedFoodForEditor: FoodItem?
    @State private var editingSchedule: DailyFoodSchedule?

    private func t(_ key: String, _ arguments: CVarArg...) -> String { language.text(key, arguments) }

    var body: some View {
        List {
            Section {
                if store.schedules.isEmpty {
                    HyseEmptyState(
                        icon: "calendar.badge.plus",
                        title: t("daily_food.empty_title"),
                        message: t("daily_food.empty_message")
                    )
                } else {
                    ForEach(store.schedules) { schedule in
                        scheduleRow(schedule)
                            .swipeActions {
                                Button(role: .destructive) { store.delete(id: schedule.id) } label: {
                                    Label(t("settings.delete"), systemImage: "trash")
                                }
                            }
                    }
                }
            } footer: {
                Text(t("daily_food.footer"))
            }
        }
        .hyseForm()
        .navigationTitle(t("daily_food.title"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    selectedFoodForEditor = nil
                    showingFoodSearch = true
                } label: {
                    Label(t("daily_food.add"), systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingFoodSearch, onDismiss: { selectedFoodForEditor = nil }) {
            if let selectedFoodForEditor {
                DailyFoodScheduleEditor(
                    food: selectedFoodForEditor,
                    foodStore: foodStore,
                    categoryStore: categoryStore,
                    frequencyStore: frequencyStore,
                    recipeStore: recipeStore,
                    userSettings: userSettings,
                    calorieStore: calorieStore
                ) { schedule in
                    store.add(schedule)
                    store.reconcileToday(calorieStore: calorieStore, categories: categoryStore.categories)
                }
            } else {
                AddEntryView(
                    foodStore: foodStore,
                    recipeStore: recipeStore,
                    categoryStore: categoryStore,
                    frequencyStore: frequencyStore,
                    userSettings: userSettings,
                    calorieStore: calorieStore,
                    availableCalories: 0,
                    category: categoryStore.categories.first ?? MealCategory(name: "meal", order: 0),
                    entryDate: Date(),
                    foodSelectionHandler: { selectedFoodForEditor = $0 },
                    dismissAfterFoodSelection: false
                )
            }
        }
        .sheet(item: $editingSchedule) { schedule in
            DailyFoodScheduleEditor(
                food: schedule.food,
                existingSchedule: schedule,
                foodStore: foodStore,
                categoryStore: categoryStore,
                frequencyStore: frequencyStore,
                recipeStore: recipeStore,
                userSettings: userSettings,
                calorieStore: calorieStore
            ) { updated in
                store.update(updated)
            }
        }
    }

    private func scheduleRow(_ schedule: DailyFoodSchedule) -> some View {
        HStack(spacing: HyseSpacing.medium) {
            Image(systemName: "fork.knife.circle.fill")
                .font(.title2)
                .foregroundStyle(HyseColor.accent)
            Button { editingSchedule = schedule } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(schedule.food.displayName(using: language))
                            .font(.headline)
                        Text("\(amountText(schedule)) · \(categoryName(schedule))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Toggle("", isOn: Binding(
                get: { schedule.isEnabled },
                set: { enabled in
                    store.setEnabled(enabled, id: schedule.id)
                    if enabled { store.reconcileToday(calorieStore: calorieStore, categories: categoryStore.categories) }
                }
            ))
            .labelsHidden()
        }
    }

    private func amountText(_ schedule: DailyFoodSchedule) -> String {
        let unit = schedule.food.unit.isVolume ? FoodUnit.milliliter : .gram
        let displayed = schedule.food.unit.converted(schedule.amount, to: unit) ?? schedule.amount
        return "\(displayed.formatted(.number.precision(.fractionLength(0...1)))) \(unit.rawValue)"
    }

    private func categoryName(_ schedule: DailyFoodSchedule) -> String {
        categoryStore.categories.first(where: { $0.id == schedule.categoryID })?.localizedName
            ?? categoryStore.categories.first(where: { $0.storageKey == schedule.categoryName })?.localizedName
            ?? schedule.categoryName
    }
}

private struct DailyFoodScheduleEditor: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var language: LanguageStore
    let food: FoodItem
    let existingSchedule: DailyFoodSchedule?
    @ObservedObject var foodStore: FoodStore
    @ObservedObject var categoryStore: CategoryStore
    @ObservedObject var frequencyStore: FrequencyStore
    @ObservedObject var recipeStore: RecipeStore
    @ObservedObject var userSettings: UserSettingsStore
    @ObservedObject var calorieStore: CalorieStore
    let save: (DailyFoodSchedule) -> Void

    @State private var selectedFood: FoodItem?
    @State private var selectedCategoryID: UUID?
    @State private var amountText = "100"
    @State private var showingFoodSearch = false

    private func t(_ key: String, _ arguments: CVarArg...) -> String { language.text(key, arguments) }
    private var amount: Double? { Double(amountText.replacingOccurrences(of: ",", with: ".")) }

    init(
        food: FoodItem,
        existingSchedule: DailyFoodSchedule? = nil,
        foodStore: FoodStore,
        categoryStore: CategoryStore,
        frequencyStore: FrequencyStore,
        recipeStore: RecipeStore,
        userSettings: UserSettingsStore,
        calorieStore: CalorieStore,
        save: @escaping (DailyFoodSchedule) -> Void
    ) {
        self.food = food
        self.existingSchedule = existingSchedule
        self.foodStore = foodStore
        self.categoryStore = categoryStore
        self.frequencyStore = frequencyStore
        self.recipeStore = recipeStore
        self.userSettings = userSettings
        self.calorieStore = calorieStore
        self.save = save
        _selectedFood = State(initialValue: food)
        _selectedCategoryID = State(initialValue: existingSchedule?.categoryID ?? categoryStore.categories.first?.id)
        if let existingSchedule {
            let unit: FoodUnit = food.unit.isVolume ? .milliliter : .gram
            let displayed = food.unit.converted(existingSchedule.amount, to: unit) ?? existingSchedule.amount
            _amountText = State(initialValue: displayed.formatted(.number.precision(.fractionLength(0...2)).locale(.current)))
        } else {
            _amountText = State(initialValue: Self.initialAmountText(for: food, entries: calorieStore.entries))
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let selectedFood {
                    configuration(for: selectedFood)
                }
            }
            .navigationTitle(t("daily_food.configure"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("app_tabs.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(t("daily_food.save"), action: saveSchedule)
                        .disabled(!canSave)
                }
            }
        }
        .sheet(isPresented: $showingFoodSearch) {
            AddEntryView(
                foodStore: foodStore,
                recipeStore: recipeStore,
                categoryStore: categoryStore,
                frequencyStore: frequencyStore,
                userSettings: userSettings,
                calorieStore: calorieStore,
                availableCalories: 0,
                category: categoryStore.categories.first ?? MealCategory(name: "meal", order: 0),
                entryDate: Date(),
                foodSelectionHandler: { select($0) }
            )
        }
    }

    private func configuration(for food: FoodItem) -> some View {
        Form {
            Section(t("daily_food.food")) {
                LabeledContent(t("daily_food.selected_food"), value: food.displayName(using: language))
                Button(t("daily_food.choose_different")) {
                    showingFoodSearch = true
                }
            }

            Section(t("daily_food.amount")) {
                HStack {
                    Text(t("daily_food.daily_amount"))
                    Spacer()
                    TextField("100", text: $amountText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 90)
                    Text(displayUnit(for: food).rawValue).foregroundStyle(.secondary)
                }
            }

            Section(t("daily_food.meal")) {
                Picker(t("daily_food.meal"), selection: $selectedCategoryID) {
                    ForEach(categoryStore.categories) { category in
                        Text(category.localizedName).tag(Optional(category.id))
                    }
                }
            }
        }
    }

    private var canSave: Bool {
        guard selectedFood != nil, let amount, amount.isFinite, amount > 0,
              selectedCategoryID != nil else { return false }
        return true
    }

    private func select(_ food: FoodItem) {
        selectedFood = food
        if !categoryStore.categories.contains(where: { $0.id == selectedCategoryID }) {
            selectedCategoryID = categoryStore.categories.first?.id
        }
        amountText = Self.initialAmountText(for: food, entries: calorieStore.entries)
    }

    private func saveSchedule() {
        guard let food = selectedFood,
              let enteredAmount = amount,
              enteredAmount.isFinite,
              enteredAmount > 0,
              let categoryID = selectedCategoryID,
              let category = categoryStore.categories.first(where: { $0.id == categoryID }) else { return }

        let storedAmount = displayUnit(for: food).converted(enteredAmount, to: food.unit) ?? enteredAmount
        save(DailyFoodSchedule(
            id: existingSchedule?.id ?? UUID(),
            food: food,
            amount: storedAmount,
            category: category,
            isEnabled: existingSchedule?.isEnabled ?? true,
            processedDayKeys: existingSchedule?.processedDayKeys ?? [],
            createdAt: existingSchedule?.createdAt ?? Date()
        ))
        dismiss()
    }

    private func displayUnit(for food: FoodItem) -> FoodUnit {
        food.unit.isVolume ? .milliliter : .gram
    }

    private static func initialAmountText(for food: FoodItem, entries: [CalorieEntry]) -> String {
        let recent = entries
            .filter { entry in
                if entry.foodItemId == food.id { return true }
                if let globalID = food.globalRecordID, !globalID.isEmpty, entry.globalFoodRecordID == globalID { return true }
                guard entry.foodItemId == nil, entry.globalFoodRecordID == nil else { return false }
                return entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    .localizedCaseInsensitiveCompare(food.name.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
            }
            .max { $0.date < $1.date }
        guard let recent else { return "100" }
        let displayUnit: FoodUnit = food.unit.isVolume ? .milliliter : .gram
        let displayed = recent.unit.converted(recent.grams, to: displayUnit) ?? recent.grams
        guard displayed.isFinite, displayed > 0 else { return "100" }
        return displayed.formatted(.number.precision(.fractionLength(0...2)).locale(.current))
    }
}
