import SwiftUI
import Combine

// Compatibility interface for existing views and settings. Access is free.
enum PremiumArea: String, Identifiable {
    case nutrition
    case training

    var id: String { rawValue }
}

@MainActor
final class PremiumAccessStore: ObservableObject {
    var hasNutrition: Bool { true }
    var hasTraining: Bool { true }

    func hasAccess(to _: PremiumArea) -> Bool { true }
    func refresh() async {}
    func updateAccount(_: AuthManager) async {}
}

// Existing navigation branches can still present this screen, but it never
// offers products, subscriptions, purchases, restoration or offer codes.
struct PremiumPaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var language: LanguageStore

    init(requestedArea _: PremiumArea? = nil) {}

    var body: some View {
        NavigationStack {
            Text(language.isGerman ? "Alle Funktionen sind kostenlos verfügbar." : "All features are available for free.")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(HyseColor.background)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(language.text("add_entry.done")) { dismiss() }
                    }
                }
        }
    }
}

struct PremiumLockedLabel: View {
    let area: PremiumArea
    var body: some View { EmptyView() }
}

struct PremiumFeatureIcon: View {
    let area: PremiumArea
    var body: some View { EmptyView() }
}
