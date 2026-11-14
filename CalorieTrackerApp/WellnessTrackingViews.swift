import Foundation
import Combine
import SwiftUI

nonisolated struct FastingSession: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let startedAt: Date
    let endedAt: Date
    let targetHours: Int

    var duration: TimeInterval { max(0, endedAt.timeIntervalSince(startedAt)) }
}

@MainActor
final class FastingStore: ObservableObject {
    @Published private(set) var startedAt: Date?
    @Published private(set) var sessions: [FastingSession] = []
    @Published var targetHours: Int { didSet { persist() } }

    private let stateKey = "fasting_tracker_state_v1"
    private struct State: Codable {
        var startedAt: Date?
        var targetHours: Int
        var sessions: [FastingSession]
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: stateKey),
           let state = try? JSONDecoder().decode(State.self, from: data) {
            startedAt = state.startedAt
            targetHours = (1...48).contains(state.targetHours) ? state.targetHours : 16
            sessions = Array(state.sessions.sorted { $0.endedAt > $1.endedAt }.prefix(30))
        } else {
            targetHours = 16
        }
    }

    var isFasting: Bool { startedAt != nil }
    var targetDuration: TimeInterval { TimeInterval(targetHours * 3_600) }

    func start(at date: Date = Date()) {
        guard startedAt == nil else { return }
        startedAt = date
        persist()
    }

    @discardableResult
    func finish(at date: Date = Date()) -> FastingSession? {
        guard let start = startedAt, date > start else { return nil }
        let session = FastingSession(id: UUID(), startedAt: start, endedAt: date, targetHours: targetHours)
        sessions.insert(session, at: 0)
        sessions = Array(sessions.prefix(30))
        startedAt = nil
        persist()
        return session
    }

    private func persist() {
        let state = State(startedAt: startedAt, targetHours: targetHours, sessions: sessions)
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: stateKey)
        }
    }
}

private struct FastingPlanOption: Identifiable {
    let hours: Int
    let titleKey: String
    var id: Int { hours }
}

private let commonFastingPlans = [
    FastingPlanOption(hours: 12, titleKey: "fasting.plan.12_12"),
    FastingPlanOption(hours: 14, titleKey: "fasting.plan.14_10"),
    FastingPlanOption(hours: 16, titleKey: "fasting.plan.16_8"),
    FastingPlanOption(hours: 18, titleKey: "fasting.plan.18_6"),
    FastingPlanOption(hours: 20, titleKey: "fasting.plan.20_4"),
    FastingPlanOption(hours: 23, titleKey: "fasting.plan.omad")
]

private func fastingPlanTitle(hours: Int, language: LanguageStore) -> String {
    if let plan = commonFastingPlans.first(where: { $0.hours == hours }) {
        return language.text(plan.titleKey)
    }
    return language.text("fasting.plan.custom_value", [hours])
}

struct StepCounterCard: View {
    @EnvironmentObject private var language: LanguageStore
    @ObservedObject var health: HealthKitManager
    let date: Date
    private let goal = 10_000

    private var steps: Int { health.steps(for: date) }

    var body: some View {
        HyseCard(accent: HyseColor.accent) {
            VStack(alignment: .leading, spacing: HyseSpacing.large) {
                HStack(spacing: HyseSpacing.medium) {
                    HyseIconBadge(icon: "figure.walk", size: 42)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(language.text("steps.title")).font(.headline)
                        Text(language.text("steps.apple_health")).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    HyseInfoButton(
                        title: language.text("steps.title"),
                        message: language.text("info.steps.body")
                    )
                    Text(steps.formatted(.number.locale(language.locale)))
                        .font(.title2.bold())
                        .monospacedDigit()
                }
                HyseProgressBar(value: Double(steps), total: Double(goal), colors: [HyseColor.accent])
                HStack {
                    Text(Calendar.autoupdatingCurrent.isDateInToday(date)
                         ? language.text("steps.today")
                         : date.formatted(.dateTime.day().month().locale(language.locale)))
                    Spacer()
                    Text(language.text("steps.goal", [goal.formatted(.number.locale(language.locale))]))
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if !health.isAuthorized {
                    Button(language.text("steps.connect_health")) { health.requestAuthorization() }
                        .buttonStyle(HyseSecondaryButtonStyle())
                }
            }
        }
        .onAppear { health.refreshSteps(for: date) }
        .onChange(of: date) { _, value in health.refreshSteps(for: value) }
    }
}

struct FastingTrackerCard: View {
    @EnvironmentObject private var language: LanguageStore
    @ObservedObject var store: FastingStore
    @State private var showingCustomDuration = false
    @State private var customTargetHours = 16

    var body: some View {
        HyseCard(accent: HyseColor.accent) {
            VStack(alignment: .leading, spacing: HyseSpacing.large) {
                HStack(spacing: HyseSpacing.medium) {
                    HyseIconBadge(icon: "timer", size: 42)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(language.text("fasting.title")).font(.headline)
                        Text(language.text(store.isFasting ? "fasting.active" : "fasting.ready"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    HyseInfoButton(
                        title: language.text("fasting.title"),
                        message: language.text("info.fasting.body")
                    )
                    Menu {
                        ForEach(commonFastingPlans) { plan in
                            Button {
                                store.targetHours = plan.hours
                            } label: {
                                if store.targetHours == plan.hours {
                                    Label(language.text(plan.titleKey), systemImage: "checkmark")
                                } else {
                                    Text(language.text(plan.titleKey))
                                }
                            }
                        }
                        Divider()
                        Button(language.text("fasting.plan.custom")) {
                            customTargetHours = store.targetHours
                            showingCustomDuration = true
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Text(fastingPlanTitle(hours: store.targetHours, language: language)).fontWeight(.semibold)
                                .lineLimit(1)
                            Image(systemName: "chevron.down").font(.caption2)
                        }
                        .padding(.horizontal, HyseSpacing.medium)
                        .frame(height: 36)
                        .hyseGlassSurface(radius: 18)
                    }
                    .disabled(store.isFasting)
                }

                if let start = store.startedAt {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        activeFast(start: start, now: context.date)
                    }
                    Button(language.text("fasting.finish")) { store.finish() }
                        .buttonStyle(HyseSecondaryButtonStyle())
                } else {
                    if let last = store.sessions.first {
                        HStack {
                            Text(language.text("fasting.last_fast"))
                            Spacer()
                            Text(duration(last.duration)).fontWeight(.semibold).monospacedDigit()
                        }
                        .font(.caption).foregroundStyle(.secondary)
                    }
                    Button(language.text("fasting.start")) { store.start() }
                        .buttonStyle(HysePrimaryButtonStyle())
                }
            }
        }
        .sheet(isPresented: $showingCustomDuration) {
            NavigationStack {
                VStack(spacing: HyseSpacing.xLarge) {
                    HyseIconBadge(icon: "timer", size: 54)
                    Text(language.text("fasting.plan.custom_duration"))
                        .font(.title3.bold())
                    Text(language.text("fasting.plan.custom_value", [customTargetHours]))
                        .font(.largeTitle.bold())
                        .monospacedDigit()
                    Stepper("", value: $customTargetHours, in: 1...48)
                        .labelsHidden()
                    Button(language.text("fasting.plan.use")) {
                        store.targetHours = customTargetHours
                        showingCustomDuration = false
                    }
                    .buttonStyle(HysePrimaryButtonStyle())
                }
                .padding(HyseSpacing.page)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(HyseBackdrop())
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(language.text("app_tabs.cancel")) { showingCustomDuration = false }
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }

    private func activeFast(start: Date, now: Date) -> some View {
        let elapsed = max(0, now.timeIntervalSince(start))
        let remaining = store.targetDuration - elapsed
        return VStack(alignment: .leading, spacing: HyseSpacing.medium) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(language.text("fasting.elapsed")).font(.caption).foregroundStyle(.secondary)
                    Text(duration(elapsed)).font(.title2.bold()).monospacedDigit()
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(remaining > 0 ? language.text("fasting.remaining") : language.text("fasting.goal_reached"))
                        .font(.caption).foregroundStyle(.secondary)
                    Text(remaining > 0 ? duration(remaining) : "+\(duration(abs(remaining)))")
                        .font(.headline).monospacedDigit().foregroundStyle(HyseColor.accent)
                }
            }
            HyseProgressBar(value: elapsed, total: store.targetDuration, colors: [HyseColor.accent])
            Text(language.text("fasting.ends", [start.addingTimeInterval(store.targetDuration).formatted(.dateTime.weekday(.abbreviated).hour().minute().locale(language.locale))]))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func duration(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval))
        return String(format: "%02d:%02d:%02d", seconds / 3_600, (seconds % 3_600) / 60, seconds % 60)
    }
}

struct ActiveFastingBanner: View {
    @EnvironmentObject private var language: LanguageStore
    @ObservedObject var store: FastingStore

    var body: some View {
        if let start = store.startedAt {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                let elapsed = max(0, context.date.timeIntervalSince(start))
                let end = start.addingTimeInterval(store.targetDuration)
                HyseCard(accent: HyseColor.accent) {
                    VStack(alignment: .leading, spacing: HyseSpacing.medium) {
                        HStack(spacing: HyseSpacing.medium) {
                            HyseIconBadge(icon: "timer", size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(language.text("fasting.active"))
                                    .font(.headline)
                                Text(fastingPlanTitle(hours: store.targetHours, language: language))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(compactDuration(elapsed))
                                .font(.title3.bold())
                                .monospacedDigit()
                                .foregroundStyle(HyseColor.accent)
                        }
                        HyseProgressBar(value: elapsed, total: store.targetDuration, colors: [HyseColor.accent])
                        HStack {
                            Text(elapsed >= store.targetDuration
                                 ? language.text("fasting.goal_reached")
                                 : language.text("fasting.top_reminder"))
                            Spacer()
                            Text(end.formatted(.dateTime.hour().minute().locale(language.locale)))
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func compactDuration(_ interval: TimeInterval) -> String {
        let minutes = max(0, Int(interval) / 60)
        return String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }
}
