import Foundation
import Combine
import WidgetKit

extension Notification.Name {
    static let hyseExternalWaterChanged = Notification.Name("hyseExternalWaterChanged")
}

final class WaterStore: ObservableObject {
    @Published private var dailyAmounts: [String: Double] = [:]

    private let storageKey = "daily_water_amounts_v1"
    private let externalAdditionPrefix = "water_external_add_v1_"
    private let appGroupID = HyseConfiguration.appGroup
    private let calendar = Calendar.current
    private var baseAmounts: [String: Double] = [:]
    private var externalAdditions: [String: Double] = [:]

    init() {
        let shared = UserDefaults(suiteName: appGroupID)
        let data = shared?.data(forKey: storageKey) ?? UserDefaults.standard.data(forKey: storageKey)
        baseAmounts = data.flatMap { try? JSONDecoder().decode([String: Double].self, from: $0) } ?? [:]
        if let data, shared?.data(forKey: storageKey) == nil { shared?.set(data, forKey: storageKey) }
        _ = refreshFromSharedStorage()
    }

    @discardableResult
    func refreshFromSharedStorage() -> Bool {
        let shared = UserDefaults(suiteName: appGroupID)
        shared?.synchronize()
        if let data = shared?.data(forKey: storageKey),
           let values = try? JSONDecoder().decode([String: Double].self, from: data) {
            baseAmounts = values
        }
        externalAdditions = Self.additions(in: shared?.dictionaryRepresentation() ?? [:], prefix: externalAdditionPrefix)
        let days = Set(baseAmounts.keys).union(externalAdditions.keys)
        let values = Dictionary(uniqueKeysWithValues: days.map { day in
            (day, max(0, baseAmounts[day, default: 0] + externalAdditions[day, default: 0]))
        })
        guard values != dailyAmounts else { return false }
        dailyAmounts = values
        return true
    }

    func amount(for date: Date) -> Double {
        dailyAmounts[dayKey(for: date), default: 0]
    }

    var allAmounts: [String: Double] { dailyAmounts }

    @discardableResult
    static func recordExternalAddition(_ milliliters: Double, for date: Date) -> Bool {
        guard milliliters.isFinite, milliliters > 0,
              let shared = UserDefaults(suiteName: HyseConfiguration.appGroup) else { return false }
        let components = Calendar.autoupdatingCurrent.dateComponents([.year, .month, .day], from: date)
        let day = String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
        shared.set(milliliters, forKey: "water_external_add_v1_\(day)_\(UUID().uuidString)")
        shared.synchronize()
        NotificationCenter.default.post(name: .hyseExternalWaterChanged, object: nil)
        WidgetCenter.shared.reloadAllTimelines()
        return true
    }

    func add(_ milliliters: Double, for date: Date) {
        guard milliliters.isFinite, milliliters > 0 else { return }
        refreshFromSharedStorage()
        let key = dayKey(for: date)
        baseAmounts[key, default: 0] += milliliters
        save()
    }

    func remove(_ milliliters: Double, for date: Date) {
        guard milliliters.isFinite, milliliters > 0 else { return }
        refreshFromSharedStorage()
        let key = dayKey(for: date)
        baseAmounts[key] = max(0, dailyAmounts[key, default: 0] - milliliters) - externalAdditions[key, default: 0]
        save()
    }

    func setAmount(_ milliliters: Double, for date: Date) {
        guard milliliters.isFinite else { return }
        refreshFromSharedStorage()
        let key = dayKey(for: date)
        baseAmounts[key] = max(0, milliliters) - externalAdditions[key, default: 0]
        save()
    }

    private func dayKey(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(baseAmounts) {
            UserDefaults.standard.set(data, forKey: storageKey)
            UserDefaults(suiteName: appGroupID)?.set(data, forKey: storageKey)
            _ = refreshFromSharedStorage()
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    private static func additions(in values: [String: Any], prefix: String) -> [String: Double] {
        var totals: [String: Double] = [:]
        for (key, rawValue) in values where key.hasPrefix(prefix) {
            let day = String(key.dropFirst(prefix.count).prefix(10))
            guard day.count == 10, let amount = rawValue as? Double, amount.isFinite, amount > 0 else { continue }
            totals[day, default: 0] += amount
        }
        return totals
    }
}
