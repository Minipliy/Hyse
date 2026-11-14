import SwiftUI

struct FirstActionOnboardingView: View {
    @EnvironmentObject private var language: LanguageStore
    let interest: TrackingInterest
    let logFood: () -> Void
    let startWorkout: () -> Void
    let explore: () -> Void

    var body: some View {
        ZStack {
            HyseBackdrop()
            VStack(spacing: HyseSpacing.xLarge) {
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(HyseColor.accent)
                Text(language.text("first_action.title"))
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                Text(language.text("first_action.subtitle"))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                VStack(spacing: HyseSpacing.medium) {
                    if interest.includesNutrition {
                        Button(action: logFood) {
                            Label(language.text("first_action.log_food"), systemImage: "fork.knife")
                        }
                        .buttonStyle(HysePrimaryButtonStyle())
                    }
                    if interest.includesTraining {
                        if interest.includesNutrition {
                            Button(action: startWorkout) {
                                Label(language.text("first_action.start_workout"), systemImage: "figure.strengthtraining.traditional")
                            }
                            .buttonStyle(HyseSecondaryButtonStyle())
                        } else {
                            Button(action: startWorkout) {
                                Label(language.text("first_action.start_workout"), systemImage: "figure.strengthtraining.traditional")
                            }
                            .buttonStyle(HysePrimaryButtonStyle())
                        }
                    }
                }
                Button(language.text("first_action.explore"), action: explore)
                    .font(.subheadline)
                Spacer()
            }
            .padding(HyseSpacing.page)
        }
    }
}
