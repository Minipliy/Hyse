import SwiftUI

struct GuestMergeView: View {
    @EnvironmentObject private var language: LanguageStore
    let entryCount: Int
    let favoriteCount: Int
    var workoutCount: Int = 0
    var recipeCount: Int = 0
    var mealPlanCount: Int = 0
    let isMerging: Bool
    let importAction: () -> Void
    let keepSeparateAction: () -> Void

    private func t(_ key: String, _ arguments: CVarArg...) -> String { language.text(key, arguments) }

    var body: some View {
        ZStack {
            HyseColor.background.ignoresSafeArea()
            VStack(spacing: HyseSpacing.xLarge) {
                Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                    .font(.system(size: 52, weight: .semibold))
                    .foregroundStyle(HyseColor.accent)
                    .accessibilityHidden(true)
                VStack(spacing: HyseSpacing.small) {
                    Text(t("guest_merge.guest_data_found")).font(.title2.bold())
                    Text(t("guest_merge.choose_whether_these_local_items_should_merged"))
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                HyseCard {
                    VStack(alignment: .leading, spacing: HyseSpacing.medium) {
                        if entryCount > 0 { Label(t("guest_merge.1_food_entries", String(describing: entryCount)), systemImage: "fork.knife") }
                        if favoriteCount > 0 { Label(t("guest_merge.1_favorites", String(describing: favoriteCount)), systemImage: "star.fill") }
                        if workoutCount > 0 { Label(t("guest_merge.training_items", workoutCount), systemImage: "figure.strengthtraining.traditional") }
                        if recipeCount > 0 { Label(t("guest_merge.recipes", recipeCount), systemImage: "book.closed.fill") }
                        if mealPlanCount > 0 { Label(t("guest_merge.meal_plan", mealPlanCount), systemImage: "calendar") }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                VStack(spacing: HyseSpacing.medium) {
                    Button(action: importAction) {
                        if isMerging { ProgressView().frame(maxWidth: .infinity) }
                        else { Text(t("guest_merge.merge_account")).frame(maxWidth: .infinity) }
                    }
                    .buttonStyle(HysePrimaryButtonStyle())
                    .disabled(isMerging)
                    Button(t("guest_merge.keep_separate"), action: keepSeparateAction)
                        .buttonStyle(HyseSecondaryButtonStyle())
                        .disabled(isMerging)
                }
            }
            .padding(HyseSpacing.page)
            .frame(maxWidth: 520)
        }
        .interactiveDismissDisabled()
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
    }
}
