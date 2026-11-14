import SwiftUI

struct FoodHubView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var language: LanguageStore
    @ObservedObject var foodStore: FoodStore
    @ObservedObject var recipeStore: RecipeStore
    @ObservedObject var categoryStore: CategoryStore
    @ObservedObject var frequencyStore: FrequencyStore
    @ObservedObject var userSettings: UserSettingsStore
    @ObservedObject var calorieStore: CalorieStore
    let availableCalories: Double
    @Binding var selectedDate: Date
    @State private var showingEntry = false

    private func t(_ key: String, _ arguments: CVarArg...) -> String { language.text(key, arguments) }

    var body: some View {
        NavigationStack {
            SavedFoodsView(foodStore: foodStore)
                .navigationTitle(t("app_tabs.food"))
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(t("add_entry.done")) { dismiss() }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showingEntry = true } label: {
                            Label(t("app_tabs.log_existing"), systemImage: "plus.circle.fill")
                        }
                    }
                }
        }
        .sheet(isPresented: $showingEntry) {
            if let category = categoryStore.categories.first {
                AddEntryView(foodStore: foodStore, recipeStore: recipeStore, categoryStore: categoryStore, frequencyStore: frequencyStore, userSettings: userSettings, calorieStore: calorieStore, availableCalories: availableCalories, category: category, entryDate: selectedDate)
            }
        }
    }
}

struct ProfileView: View {
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var language: LanguageStore
    @State private var showingLogin = false
    @State private var showingEmail = false
    @State private var showingPassword = false
    @ObservedObject var settingsStore: UserSettingsStore
    @ObservedObject var categoryStore: CategoryStore
    @ObservedObject var foodStore: FoodStore
    @ObservedObject var calorieStore: CalorieStore
    @ObservedObject var recipeStore: RecipeStore
    @ObservedObject var frequencyStore: FrequencyStore
    @ObservedObject var healthKitManager: HealthKitManager
    private func t(_ key: String, _ arguments: CVarArg...) -> String { language.text(key, arguments) }

    var body: some View {
        NavigationStack {
            List {
                if authManager.isLoggedIn {
                    Section {
                        HyseCard(accent: HyseColor.accent) {
                        HStack(spacing: HyseSpacing.medium) {
                            ProfileAvatarView(size: 56, editable: true)
                            VStack(alignment: .leading) {
                                Text(authManager.accountName).font(.headline)
                                Text(authManager.accountEmail).font(.subheadline).foregroundStyle(.secondary)
                                Text(t("profile.tap_avatar_to_change")).font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                        }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                    }
                    Section(t("app_tabs.account_management")) {
                        Button { showingEmail = true } label: { Label(t("app_tabs.change_email_address"), systemImage: "envelope.badge") }
                        Button { showingPassword = true } label: { Label(t("app_tabs.password_security"), systemImage: "lock.shield") }
                    }
                    .hyseGlassListRows(accent: HyseColor.accent)
                } else {
                    HyseEmptyState(icon: "person.crop.circle.badge.plus", title: t("app_tabs.no_account_connected"), message: t("app_tabs.use_hyse_locally_sign_in_sync_data"), actionTitle: t("app_tabs.sign_in"), action: { showingLogin = true })
                        .hyseGlassListRows(accent: HyseColor.accent)
                }
                Section(t("content.settings")) {
                    NavigationLink {
                        SettingsView(settingsStore: settingsStore, categoryStore: categoryStore, foodStore: foodStore, calorieStore: calorieStore, recipeStore: recipeStore, frequencyStore: frequencyStore, healthKitManager: healthKitManager)
                    } label: { Label(t("content.settings"), systemImage: "gearshape.fill") }
                }
                .hyseGlassListRows(accent: HyseColor.accent)
            }
            .hyseForm()
            .navigationTitle(t("app_tabs.profile"))
        }
        .sheet(isPresented: $showingLogin) { LoginView().environmentObject(authManager) }
        .sheet(isPresented: $showingEmail) { EmailChangeView().environmentObject(authManager).environmentObject(language) }
        .sheet(isPresented: $showingPassword) { PasswordManagementView().environmentObject(authManager).environmentObject(language) }
    }
}

struct StreakDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var language: LanguageStore
    @ObservedObject var calorieStore: CalorieStore
    @ObservedObject var trainingStore: TrainingStore
    @ObservedObject var rewards: StreakRewardsStore
    @State private var purchaseCelebration: FreezePurchaseEvent?
    private func t(_ key: String, _ arguments: CVarArg...) -> String { language.text(key, arguments) }

    private enum FreezeKind {
        case nutrition
        case training

        var icon: String {
            switch self {
            case .nutrition: "fork.knife"
            case .training: "figure.strengthtraining.traditional"
            }
        }
    }

    private struct FreezePurchaseEvent: Identifiable {
        let id = UUID()
        let kind: FreezeKind
    }

    private var recentWeek: [Date] {
        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: Date())
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0 - 6, to: today) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                HyseNutritionBackdrop()
                ScrollView {
                    VStack(alignment: .leading, spacing: HyseSpacing.section) {
                        streakHero
                        weeklyTrainingStreakHero
                        streakShop

                        VStack(alignment: .leading, spacing: HyseSpacing.medium) {
                            Text(t("app_tabs.last_seven_days").uppercased())
                                .font(.caption.weight(.heavy))
                                .tracking(1.1)
                                .foregroundStyle(.secondary)
                            HStack(spacing: 0) {
                                ForEach(recentWeek, id: \.self) { day in
                                    streakDay(day)
                                        .frame(maxWidth: .infinity)
                                }
                            }
                            .padding(.vertical, HyseSpacing.medium)
                            .hyseGlassSurface(radius: HyseRadius.card, tint: calorieStore.hasStreakActivityToday ? HyseColor.streakFire : nil)
                        }

                        VStack(alignment: .leading, spacing: HyseSpacing.medium) {
                            Text(t("app_tabs.recent_active_days").uppercased())
                                .font(.caption.weight(.heavy))
                                .tracking(1.1)
                                .foregroundStyle(.secondary)
                            if calorieStore.activeDays.isEmpty {
                                HyseEmptyState(icon: "calendar.badge.plus", title: t("app_tabs.streak_starts_first_meal"), message: t("app_tabs.multiple_entries_on_same_calendar_day_count"))
                            } else {
                                ForEach(calorieStore.activeDays.prefix(14), id: \.self) { day in
                                    HStack(spacing: HyseSpacing.medium) {
                                        Image(systemName: "checkmark")
                                            .font(.caption.bold())
                                            .foregroundStyle(HyseColor.streakFire)
                                            .frame(width: 30, height: 30)
                                            .background(HyseColor.streakFire.opacity(0.11), in: Circle())
                                        Text(day.formatted(.dateTime.weekday(.wide).day().month().year().locale(language.locale)))
                                            .font(.subheadline.weight(.medium))
                                        Spacer()
                                    }
                                    .padding(HyseSpacing.medium)
                                    .hyseGlassSurface(radius: HyseRadius.control)
                                }
                            }
                        }
                    }
                    .padding(HyseSpacing.page)
                    .padding(.bottom, HyseSpacing.section)
                }
            }
            .navigationTitle(t("app_tabs.streak"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(t("add_entry.done")) { dismiss() } } }
        }
        .overlay {
            if let purchaseCelebration {
                StreakFreezePurchaseCelebration(
                    icon: purchaseCelebration.kind.icon,
                    title: t("streak_rewards.purchase_success")
                )
                .id(purchaseCelebration.id)
                .transition(.opacity.combined(with: .scale(scale: 0.82)))
                .allowsHitTesting(false)
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.72), value: purchaseCelebration?.id)
        .presentationDragIndicator(.visible)
    }

    private var streakHero: some View {
        let activeColor = calorieStore.hasStreakActivityToday ? HyseColor.streakFire : Color.secondary
        return HyseCard(accent: activeColor) {
            HStack(spacing: HyseSpacing.xLarge) {
                ZStack {
                    Circle().fill(activeColor.opacity(0.11))
                    Circle().stroke(activeColor.opacity(0.24), lineWidth: 1)
                    Image(systemName: "flame.fill")
                        .font(.system(size: 38, weight: .bold))
                        .foregroundStyle(activeColor)
                }
                .frame(width: 82, height: 82)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(calorieStore.currentStreak)")
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Text(t("app_tabs.days"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Text(t(calorieStore.hasStreakActivityToday ? "app_tabs.streak_active_today" : "app_tabs.streak_open_today"))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(activeColor)
                    HStack(spacing: 5) {
                        Image(systemName: "trophy.fill")
                        Text("\(t("app_tabs.best")): \(calorieStore.longestStreak)")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 5)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var weeklyTrainingStreakHero: some View {
        let stats = trainingStore.statistics
        let isActive = stats.trainedThisWeek
        let activeColor = isActive ? HyseColor.streakFire : Color.secondary
        return HyseCard(accent: activeColor) {
            HStack(spacing: HyseSpacing.xLarge) {
                ZStack {
                    Circle().fill(activeColor.opacity(0.11))
                    Circle().stroke(activeColor.opacity(0.24), lineWidth: 1)
                    Image(systemName: isActive ? "figure.strengthtraining.traditional" : "figure.strengthtraining.functional")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(activeColor)
                }
                .frame(width: 82, height: 82)

                VStack(alignment: .leading, spacing: 3) {
                    Text(t("training.weekly_streak.title"))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(stats.currentStreak)")
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Text(t("app_tabs.weeks"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Text(t(isActive ? "training.weekly_streak.completed" : "training.weekly_streak.pending"))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(activeColor)
                    Text(t("training.weekly_streak.best", stats.longestStreak))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var streakShop: some View {
        HyseCard(accent: HyseColor.accent) {
            VStack(alignment: .leading, spacing: HyseSpacing.large) {
                HStack(spacing: HyseSpacing.medium) {
                    HyseIconBadge(icon: "snowflake", size: 42)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t("streak_rewards.currency"))
                            .font(.headline)
                        Text(t("streak_rewards.balance", rewards.iceCrystals))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(HyseColor.accent)
                    }
                    Spacer()
                    HyseInfoButton(title: t("streak_rewards.info_title"), message: t("streak_rewards.info_message"))
                }

                purchaseRow(
                    icon: "fork.knife",
                    title: t("streak_rewards.food_freeze"),
                    inventory: rewards.nutritionFreezeCount,
                    cost: StreakRewardsStore.nutritionFreezeCost,
                    kind: .nutrition,
                    canBuy: rewards.iceCrystals >= StreakRewardsStore.nutritionFreezeCost && rewards.nutritionFreezeCount < StreakRewardsStore.maximumFreezeCount,
                    action: rewards.buyNutritionFreeze
                )
                Divider()
                purchaseRow(
                    icon: "figure.strengthtraining.traditional",
                    title: t("streak_rewards.training_freeze"),
                    inventory: rewards.trainingFreezeCount,
                    cost: StreakRewardsStore.trainingFreezeCost,
                    kind: .training,
                    canBuy: rewards.iceCrystals >= StreakRewardsStore.trainingFreezeCost && rewards.trainingFreezeCount < StreakRewardsStore.maximumFreezeCount,
                    action: rewards.buyTrainingFreeze
                )

                Text(t("streak_rewards.automatic_use"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func purchaseRow(
        icon: String,
        title: String,
        inventory: Int,
        cost: Int,
        kind: FreezeKind,
        canBuy: Bool,
        action: @escaping () -> Bool
    ) -> some View {
        HStack(spacing: HyseSpacing.medium) {
            Image(systemName: icon)
                .foregroundStyle(HyseColor.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(t("streak_rewards.inventory_limit", inventory, StreakRewardsStore.maximumFreezeCount))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(inventory >= StreakRewardsStore.maximumFreezeCount ? t("streak_rewards.max_reached") : t("streak_rewards.buy", cost)) {
                guard action() else { return }
                showPurchaseCelebration(for: kind)
            }
                .buttonStyle(.borderedProminent)
                .disabled(!canBuy)
        }
    }

    private func showPurchaseCelebration(for kind: FreezeKind) {
        let event = FreezePurchaseEvent(kind: kind)
        withAnimation { purchaseCelebration = event }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.8))
            guard purchaseCelebration?.id == event.id else { return }
            withAnimation(.easeOut(duration: 0.28)) { purchaseCelebration = nil }
        }
    }

    private func streakDay(_ day: Date) -> some View {
        let calendar = Calendar.autoupdatingCurrent
        let isActive = calorieStore.activeDays.contains { calendar.isDate($0, inSameDayAs: day) }
        let isFrozen = calorieStore.streakFrozenDayKeys.contains(StreakTracker.dayKey(for: day, calendar: calendar))
        let isToday = calendar.isDateInToday(day)
        let color = isActive ? HyseColor.streakFire : (isFrozen ? HyseColor.accent : Color.secondary)
        return VStack(spacing: 7) {
            Text(day.formatted(.dateTime.weekday(.narrow).locale(language.locale)).uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            ZStack {
                Circle().fill(color.opacity(isActive ? 0.14 : 0.07))
                if isToday { Circle().stroke(color.opacity(0.55), lineWidth: 1.5) }
                Image(systemName: isActive ? "flame.fill" : (isFrozen ? "snowflake" : "circle"))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(color)
            }
            .frame(width: 34, height: 34)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(day.formatted(.dateTime.weekday(.wide).day().month().locale(language.locale)))
        .accessibilityValue(isActive ? t("app_tabs.streak_active_today") : (isFrozen ? t("streak_rewards.day_frozen") : t("app_tabs.streak_open_today")))
    }
}

private struct StreakFreezePurchaseCelebration: View {
    let icon: String
    let title: String
    @State private var isAnimated = false

    var body: some View {
        ZStack {
            Color.black.opacity(isAnimated ? 0.16 : 0)
                .ignoresSafeArea()

            VStack(spacing: HyseSpacing.medium) {
                ZStack {
                    ForEach(0..<8, id: \.self) { index in
                        Image(systemName: "snowflake")
                            .font(.caption.bold())
                            .foregroundStyle(HyseColor.accent.opacity(0.82))
                            .offset(y: isAnimated ? -72 : -20)
                            .rotationEffect(.degrees(Double(index) * 45))
                    }

                    Circle()
                        .fill(HyseColor.accent.gradient)
                        .frame(width: 92, height: 92)
                        .shadow(color: HyseColor.accent.opacity(0.35), radius: 22)
                    Image(systemName: icon)
                        .font(.system(size: 35, weight: .bold))
                        .foregroundStyle(.white)
                        .overlay(alignment: .topTrailing) {
                            Image(systemName: "snowflake")
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                                .offset(x: 10, y: -9)
                        }
                }
                .scaleEffect(isAnimated ? 1 : 0.45)

                Text(title)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .opacity(isAnimated ? 1 : 0)
                    .offset(y: isAnimated ? 0 : 8)
            }
            .padding(.horizontal, HyseSpacing.xLarge)
            .padding(.vertical, HyseSpacing.large)
            .background(HyseColor.surface, in: RoundedRectangle(cornerRadius: HyseRadius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: HyseRadius.card, style: .continuous).stroke(HyseColor.accent.opacity(0.3)))
            .shadow(color: .black.opacity(0.18), radius: 28, y: 12)
        }
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.62)) {
                isAnimated = true
            }
        }
    }
}
