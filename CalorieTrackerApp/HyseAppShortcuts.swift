import AppIntents
import UIKit
import WidgetKit

private enum HyseShortcutError: LocalizedError {
    case invalidWaterAmount
    case cannotOpenApp
    case cannotSaveWater

    var errorDescription: String? {
        switch self {
        case .invalidWaterAmount: String(localized: "shortcut.water.invalid_amount")
        case .cannotOpenApp: String(localized: "shortcut.cannot_open_app")
        case .cannotSaveWater: String(localized: "shortcut.water.cannot_save")
        }
    }
}

struct LogWaterShortcutIntent: AppIntent {
    static var title: LocalizedStringResource = "shortcut.water.title"
    static var description = IntentDescription("shortcut.water.description")

    @Parameter(title: "shortcut.water.amount")
    var amountMilliliters: Int

    init() { amountMilliliters = 250 }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard (1...2000).contains(amountMilliliters) else { throw HyseShortcutError.invalidWaterAmount }
        guard WaterStore.recordExternalAddition(Double(amountMilliliters), for: Date()) else { throw HyseShortcutError.cannotSaveWater }
        return .result()
    }
}

struct OpenFoodLogShortcutIntent: AppIntent {
    static var title: LocalizedStringResource = "shortcut.food.title"
    static var description = IntentDescription("shortcut.food.description")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let url = URL(string: "hyseapp://food"), await UIApplication.shared.open(url) else { throw HyseShortcutError.cannotOpenApp }
        return .result()
    }
}

struct StartWorkoutShortcutIntent: AppIntent {
    static var title: LocalizedStringResource = "shortcut.workout.title"
    static var description = IntentDescription("shortcut.workout.description")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let url = URL(string: "hyseapp://training/start"), await UIApplication.shared.open(url) else { throw HyseShortcutError.cannotOpenApp }
        return .result()
    }
}

struct StartRoutineShortcutIntent: AppIntent {
    static var title: LocalizedStringResource = "shortcut.routine.title"
    static var description = IntentDescription("shortcut.routine.description")
    static var openAppWhenRun = true

    @Parameter(title: "shortcut.routine.name")
    var routineName: String

    init() { routineName = "" }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard !routineName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            guard let url = URL(string: "hyseapp://training"), await UIApplication.shared.open(url) else { throw HyseShortcutError.cannotOpenApp }
            return .result()
        }
        var components = URLComponents()
        components.scheme = "hyseapp"
        components.host = "training"
        components.path = "/start"
        components.queryItems = [URLQueryItem(name: "routine", value: routineName)]
        guard let url = components.url, await UIApplication.shared.open(url) else { throw HyseShortcutError.cannotOpenApp }
        return .result()
    }
}

struct HyseAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogWaterShortcutIntent(),
            phrases: ["Log water in \(.applicationName)", "Wasser in \(.applicationName) erfassen"],
            shortTitle: "shortcut.water.short",
            systemImageName: "drop.fill"
        )
        AppShortcut(
            intent: OpenFoodLogShortcutIntent(),
            phrases: ["Log food in \(.applicationName)", "Ernährung in \(.applicationName) erfassen"],
            shortTitle: "shortcut.food.short",
            systemImageName: "fork.knife"
        )
        AppShortcut(
            intent: StartWorkoutShortcutIntent(),
            phrases: ["Start a workout in \(.applicationName)", "Workout in \(.applicationName) starten"],
            shortTitle: "shortcut.workout.short",
            systemImageName: "figure.strengthtraining.traditional"
        )
        AppShortcut(
            intent: StartRoutineShortcutIntent(),
            phrases: ["Start a routine in \(.applicationName)", "Starte eine Routine in \(.applicationName)"],
            shortTitle: "shortcut.routine.short",
            systemImageName: "list.bullet.clipboard"
        )
    }
}
