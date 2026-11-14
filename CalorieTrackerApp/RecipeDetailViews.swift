import SwiftUI
import UIKit

private struct RecipeShareDestination: Identifiable {
    let id = UUID()
    let url: URL
}

private struct RecipeShareActivitySheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct RecipeDetailsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var language: LanguageStore
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var mealPlan: MealPlanStore
    @EnvironmentObject private var categoryStore: CategoryStore
    let recipe: Recipe
    @ObservedObject var foodStore: FoodStore
    @ObservedObject var recipeStore: RecipeStore
    var onChooseForEntry: ((Recipe, Double) -> Void)? = nil
    @State private var showingEdit = false
    @State private var showingPlan = false
    @State private var targetServings: Double = 0
    @State private var checkedIngredients: Set<UUID> = []
    @State private var remotePhotoData: Data?
    @State private var completedSteps: Set<Int> = []
    @State private var isPublishing = false
    @State private var showingLoginPrompt = false
    @State private var showingLogin = false
    @State private var pendingShareAfterLogin = false
    @State private var shareError: String?
    @State private var shareDestination: RecipeShareDestination?

    private var current: Recipe {
        recipe.origin == .personal ? recipeStore.recipes.first(where: { $0.id == recipe.id }) ?? recipe : recipe
    }
    private var servings: Double { targetServings > 0 ? targetServings : current.servings }
    private var isFavorite: Bool {
        current.origin == .global ? recipeStore.isGlobalFavorite(current) : current.isFavorite
    }
    private var description: String {
        let value = current.displayDescription
        return value == current.preparationSteps.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) ? "" : value
    }
    private var photoData: Data? {
        RecipeImageStore.data(for: current.imageFileName)
            ?? RecipeImageStore.cachedRemoteData(remoteID: current.remoteID, fileName: current.remoteImageFileName)
            ?? remotePhotoData
    }

    var body: some View {
        NavigationStack {
            GeometryReader { viewport in
                ScrollView {
                VStack(alignment: .leading, spacing: HyseSpacing.large) {
                    if let data = photoData, let image = UIImage(data: data) {
                        GeometryReader { photo in
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: photo.size.width, height: 260)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: HyseRadius.card))
                                .accessibilityLabel(current.name)
                        }
                        .frame(height: 260)
                    }
                    VStack(alignment: .leading, spacing: HyseSpacing.small) {
                        Text(current.name).font(.largeTitle.bold()).foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        if !description.isEmpty {
                            Text(description).font(.body).foregroundStyle(.secondary)
                        }
                        HStack(spacing: HyseSpacing.medium) {
                            Label("\(Int(current.caloriesPerServing)) kcal", systemImage: "flame")
                            if let minutes = current.preparationMinutes, minutes > 0 {
                                Label("\(minutes) \(language.text("recipes.minutes"))", systemImage: "clock")
                            }
                        }
                        .font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                    }
                    if !current.filters.isEmpty { RecipeFilterBadges(filters: current.filters) }
                    HyseCard {
                        VStack(alignment: .leading, spacing: HyseSpacing.medium) {
                            HStack {
                                HyseSectionHeading(title: language.text("recipe_editor.ingredients"), icon: "basket", color: .secondary)
                                Spacer()
                                Text(language.text("recipes.portions_value", [servings.formatted(.number.precision(.fractionLength(0...1)))]))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Stepper(value: $targetServings, in: 0.5...100, step: 0.5) {
                                Text(language.text("recipes.adjust_servings"))
                                    .font(.subheadline.weight(.medium))
                            }
                            ForEach(current.ingredients) { ingredient in
                                Button {
                                    if !checkedIngredients.insert(ingredient.id).inserted { checkedIngredients.remove(ingredient.id) }
                                } label: {
                                    HStack(spacing: HyseSpacing.medium) {
                                        Image(systemName: checkedIngredients.contains(ingredient.id) ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(checkedIngredients.contains(ingredient.id) ? HyseColor.success : .secondary)
                                        Text(ingredient.food.displayName(using: language))
                                            .strikethrough(checkedIngredients.contains(ingredient.id))
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .fixedSize(horizontal: false, vertical: true)
                                        Text("\((ingredient.grams * servings / max(current.servings, 0.1)).formatted(.number.precision(.fractionLength(0...1)))) \(ingredient.unit.rawValue)")
                                            .foregroundStyle(.secondary).monospacedDigit()
                                            .fixedSize()
                                    }
                                    .font(.subheadline).foregroundStyle(.primary)
                                    .padding(.vertical, HyseSpacing.small)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    HyseCard {
                        VStack(alignment: .leading, spacing: HyseSpacing.medium) {
                            HyseSectionHeading(title: language.text("recipes.preparation_steps"), icon: "list.number", color: .secondary)
                            if current.preparationSteps.isEmpty {
                                Text(language.text("recipes.no_steps"))
                                    .font(.subheadline).foregroundStyle(.secondary)
                            } else {
                                ForEach(Array(current.preparationSteps.enumerated()), id: \.offset) { index, step in
                                    Button {
                                        if !completedSteps.insert(index).inserted { completedSteps.remove(index) }
                                    } label: {
                                        HStack(alignment: .top, spacing: HyseSpacing.medium) {
                                            Text("\(index + 1)")
                                                .font(.subheadline.bold())
                                                .frame(width: 30, height: 30)
                                                .background(HyseColor.elevatedSurface, in: Circle())
                                            Text(step)
                                                .font(.body).multilineTextAlignment(.leading)
                                                .strikethrough(completedSteps.contains(index))
                                            Spacer(minLength: 0)
                                            if completedSteps.contains(index) { Image(systemName: "checkmark").foregroundStyle(HyseColor.success) }
                                        }
                                        .foregroundStyle(completedSteps.contains(index) ? .secondary : .primary)
                                        .padding(.vertical, HyseSpacing.small)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    HyseCard {
                        VStack(alignment: .leading, spacing: HyseSpacing.medium) {
                            HyseSectionHeading(title: language.text("recipe_editor.per_serving"), icon: "chart.bar", color: .secondary)
                            NutrientOverview(nutrients: current.nutrientsPerServing, amountLabel: language.text("recipe_editor.one_serving"), kcalColor: .primary)
                        }
                    }
                    Button { showingPlan = true } label: {
                        Label(language.text("meal_plan.add"), systemImage: "calendar.badge.plus")
                    }.buttonStyle(HyseSecondaryButtonStyle())
                    if current.origin == .personal {
                        if current.shareRecordID != nil {
                            Button(role: .destructive) { Task { await revokeShare() } } label: {
                                Label(language.text("recipes.revoke_link"), systemImage: "link.badge.minus")
                            }
                        }
                    } else {
                        Button { recipeStore.saveGlobalRecipe(current); dismiss() } label: {
                            Label(language.text("recipes.save_to_my_recipes"), systemImage: "square.and.arrow.down")
                        }.buttonStyle(HyseSecondaryButtonStyle())
                    }
                }
                .frame(width: max(0, viewport.size.width - 2 * HyseSpacing.page), alignment: .leading)
                .padding(.horizontal, HyseSpacing.page)
                .padding(.vertical, HyseSpacing.page)
                }
            }
            .background(HyseNutritionBackdrop())
            .navigationTitle(current.name)
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: HyseSpacing.small) {
                    if let onChooseForEntry {
                        Button { onChooseForEntry(current, servings) } label: {
                            Label(language.text("add_entry.select_recipe"), systemImage: "plus")
                        }
                        .buttonStyle(HysePrimaryButtonStyle())
                    }
                    if current.origin == .personal {
                        if dynamicTypeSize.isAccessibilitySize {
                            editButton.buttonStyle(HyseSecondaryButtonStyle())
                            if onChooseForEntry != nil {
                                shareButton.buttonStyle(HyseSecondaryButtonStyle())
                            } else {
                                shareButton.buttonStyle(HysePrimaryButtonStyle())
                            }
                        } else {
                            HStack(spacing: HyseSpacing.small) {
                                editButton.buttonStyle(HyseSecondaryButtonStyle())
                                    .frame(width: 122)
                                if onChooseForEntry != nil {
                                    shareButton.buttonStyle(HyseSecondaryButtonStyle())
                                } else {
                                    shareButton.buttonStyle(HysePrimaryButtonStyle())
                                }
                            }
                        }
                    } else if onChooseForEntry != nil {
                        shareButton.buttonStyle(HyseSecondaryButtonStyle())
                    } else {
                        shareButton.buttonStyle(HysePrimaryButtonStyle())
                    }
                }
                .padding(.horizontal, HyseSpacing.page)
                .padding(.vertical, HyseSpacing.small)
                .background(HyseColor.background)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        if current.origin == .global { recipeStore.toggleGlobalFavorite(current) }
                        else { var value = current; value.isFavorite.toggle(); recipeStore.update(value) }
                    } label: { Image(systemName: isFavorite ? "star.fill" : "star") }
                        .accessibilityLabel(language.text(isFavorite ? "add_entry.remove_from_favorites" : "add_entry.add_favorites"))
                }
                ToolbarItem(placement: .confirmationAction) { Button("add_entry.done") { dismiss() } }
            }
            .onAppear { if targetServings == 0 { targetServings = min(100, max(0.5, current.servings)) } }
            .task(id: current.remoteImageFileName) {
                guard photoData == nil, let remoteID = current.remoteID,
                      let fileName = current.remoteImageFileName,
                      authManager.isLoggedIn else { return }
                if let data = await RecipeSyncService.shared.downloadImage(remoteID: remoteID, fileName: fileName, token: authManager.token) {
                    RecipeImageStore.cacheRemote(data, remoteID: remoteID, fileName: fileName)
                    remotePhotoData = data
                }
            }
            .sheet(isPresented: $showingEdit) { RecipeEditorView(foodStore: foodStore, recipeStore: recipeStore, recipe: current) }
            .sheet(isPresented: $showingPlan) { MealPlanAddView(plan: mealPlan, categories: categoryStore, recipe: current) }
            .sheet(item: $shareDestination) { RecipeShareActivitySheet(url: $0.url) }
            .sheet(isPresented: $showingLogin) { LoginView().environmentObject(authManager) }
            .alert(language.text("recipes.share_error_title"), isPresented: $showingLoginPrompt) {
                Button(language.text("app_tabs.sign_in")) { pendingShareAfterLogin = true; showingLogin = true }
                Button(language.text("app_tabs.cancel"), role: .cancel) {}
            } message: { Text(language.text("recipes.share_requires_account")) }
            .alert(language.text("recipes.share_error_title"), isPresented: Binding(get: { shareError != nil }, set: { if !$0 { shareError = nil } })) {
                Button(language.text("add_entry.done")) { shareError = nil }
            } message: { Text(shareError ?? "") }
            .onChange(of: authManager.isLoggedIn) { _, loggedIn in
                if loggedIn && pendingShareAfterLogin {
                    pendingShareAfterLogin = false
                    showingLogin = false
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(350))
                        await share()
                    }
                }
            }
        }
    }

    private var shareButton: some View {
        Button { Task { await share() } } label: {
            if isPublishing { ProgressView().frame(maxWidth: .infinity) }
            else { Label(language.text("recipes.share_link"), systemImage: "square.and.arrow.up") }
        }
        .disabled(isPublishing)
    }

    private var editButton: some View {
        Button { showingEdit = true } label: {
            Label(language.text("recipes.edit_short"), systemImage: "pencil")
        }
        .accessibilityLabel(language.text("recipe_editor.edit_recipe"))
    }

    private func share() async {
        guard !isPublishing else { return }
        if current.origin == .global, let id = current.globalRecordID ?? current.remoteID,
           let url = RecipeShareLink.url(id: id, isGerman: language.isGerman) {
            shareDestination = RecipeShareDestination(url: url)
            return
        }
        isPublishing = true
        defer { isPublishing = false }
        await authManager.refreshSession(force: true)
        guard authManager.isLoggedIn, !authManager.token.isEmpty else {
            showingLoginPrompt = true
            return
        }
        let accountID = authManager.accountID
        let token = authManager.token
        let recipeToShare = current
        do {
            let id = try await RecipeShareService.shared.publish(recipe: recipeToShare, ownerID: accountID, token: token)
            guard authManager.accountID == accountID else { return }
            var updated = recipeStore.recipes.first(where: { $0.id == recipeToShare.id }) ?? recipeToShare
            updated.shareRecordID = id
            recipeStore.update(updated)
            if let url = RecipeShareLink.url(id: id, isGerman: language.isGerman) {
                shareDestination = RecipeShareDestination(url: url)
            }
        } catch RecipeShareError.server(let status) {
            shareError = "\(language.text("recipes.share_failed")) (HTTP \(status))"
        } catch { shareError = language.text("recipes.share_failed") }
    }

    private func revokeShare() async {
        guard let id = current.shareRecordID, authManager.isLoggedIn else { return }
        do {
            try await RecipeShareService.shared.revoke(id: id, token: authManager.token)
            var updated = current
            updated.shareRecordID = nil
            recipeStore.update(updated)
        } catch { shareError = language.text("recipes.revoke_failed") }
    }
}

struct SharedRecipeDetailView: View {
    @EnvironmentObject private var language: LanguageStore
    let recipe: SharedRecipe

    var body: some View {
        GeometryReader { viewport in
            ScrollView {
            VStack(alignment: .leading, spacing: HyseSpacing.large) {
                if let url = recipe.imageURL {
                    GeometryReader { photo in
                        AsyncImage(url: url) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Rectangle().fill(HyseColor.elevatedSurface)
                        }
                        .frame(width: photo.size.width, height: 240)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: HyseRadius.card))
                    }
                    .frame(height: 240)
                }
                Text(recipe.snapshot.name).font(.largeTitle.bold())
                    .fixedSize(horizontal: false, vertical: true)
                if !recipe.snapshot.description.isEmpty { Text(recipe.snapshot.description).foregroundStyle(.secondary) }
                HStack {
                    Label("\(Int(recipe.snapshot.kcal)) kcal", systemImage: "flame")
                    Label("\(Int(recipe.snapshot.servings))", systemImage: "person.2")
                    if let minutes = recipe.snapshot.minutes { Label("\(minutes) min", systemImage: "clock") }
                }.font(.subheadline).foregroundStyle(.secondary)
                HyseCard {
                    VStack(alignment: .leading, spacing: HyseSpacing.medium) {
                        HyseSectionHeading(title: language.text("recipe_editor.ingredients"), icon: "basket", color: .secondary)
                        ForEach(Array(recipe.snapshot.ingredients.enumerated()), id: \.offset) { _, item in
                            HStack {
                                Text(item.name)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text("\(item.amount.formatted(.number.precision(.fractionLength(0...1)))) \(item.unit)")
                                    .foregroundStyle(.secondary)
                                    .fixedSize()
                            }
                        }
                    }
                }
                HyseCard {
                    VStack(alignment: .leading, spacing: HyseSpacing.medium) {
                        HyseSectionHeading(title: language.text("recipes.preparation_steps"), icon: "list.number", color: .secondary)
                        ForEach(Array(recipe.snapshot.steps.enumerated()), id: \.offset) { index, step in
                            HStack(alignment: .top, spacing: HyseSpacing.medium) {
                                Text("\(index + 1).").fontWeight(.bold)
                                Text(step)
                            }
                        }
                    }
                }
            }
            .frame(width: max(0, viewport.size.width - 2 * HyseSpacing.page), alignment: .leading)
            .padding(.horizontal, HyseSpacing.page)
            .padding(.vertical, HyseSpacing.page)
            }
        }
        .background(HyseNutritionBackdrop())
        .navigationTitle(recipe.snapshot.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
