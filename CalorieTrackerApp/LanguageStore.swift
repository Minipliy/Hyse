import Foundation
import Combine

nonisolated enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case german = "de"

    var id: String { rawValue }
    var localeIdentifier: String { self == .german ? "de_DE" : "en_US" }
    var displayNameKey: String { self == .german ? "language.german" : "language.english" }

    static var persisted: AppLanguage {
        if LanguagePreference.persisted == .system { return LanguageStore.systemLanguage }
        return AppLanguage(rawValue: UserDefaults.standard.string(forKey: LanguageStore.storageKey) ?? "") ?? .english
    }
}

nonisolated enum LanguagePreference: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case german = "de"

    var id: String { rawValue }
    var displayNameKey: String {
        switch self {
        case .system: return "language.system"
        case .english: return "language.english"
        case .german: return "language.german"
        }
    }

    static var persisted: LanguagePreference {
        if let raw = UserDefaults.standard.string(forKey: LanguageStore.preferenceStorageKey),
           let value = LanguagePreference(rawValue: raw) { return value }
        // Preserve an explicit choice made by existing users. New installs use
        // the device language until the user selects a manual override.
        if let legacy = UserDefaults.standard.string(forKey: LanguageStore.storageKey),
           let value = LanguagePreference(rawValue: legacy) { return value }
        return .system
    }
}

/// App-wide localization source. English is authoritative and is also used as
/// the fallback for every missing selected-language value.
final class LanguageStore: ObservableObject {
    nonisolated static let storageKey = "app_language_v1"
    nonisolated static let preferenceStorageKey = "app_language_preference_v2"
    private static let appGroupID = HyseConfiguration.appGroup

    @Published private(set) var language: AppLanguage
    @Published var preference: LanguagePreference {
        didSet {
            applyPreference()
        }
    }

    init() {
        let savedPreference = LanguagePreference.persisted
        preference = savedPreference
        language = savedPreference.resolvedLanguage
        persist()
    }

    nonisolated static var systemLanguage: AppLanguage {
        let preferred = Locale.preferredLanguages.first?.lowercased() ?? "en"
        return preferred == "de" || preferred.hasPrefix("de-") ? .german : .english
    }

    func applySyncedPreference(_ rawValue: String) {
        preference = LanguagePreference(rawValue: rawValue) ?? .english
    }

    private func applyPreference() {
        language = preference.resolvedLanguage
        persist()
    }

    private func persist() {
        UserDefaults.standard.set(preference.rawValue, forKey: Self.preferenceStorageKey)
        UserDefaults.standard.set(language.rawValue, forKey: Self.storageKey)
        let shared = UserDefaults(suiteName: Self.appGroupID)
        shared?.set(preference.rawValue, forKey: Self.preferenceStorageKey)
        shared?.set(language.rawValue, forKey: Self.storageKey)
    }

    var isGerman: Bool { language == .german }
    var locale: Locale { Locale(identifier: language.localeIdentifier) }

    func text(_ key: String, _ arguments: [CVarArg] = []) -> String {
        Self.formattedString(key, language: language, arguments: arguments)
    }

    nonisolated static func formattedString(_ key: String, language: AppLanguage = .persisted, arguments: [CVarArg] = []) -> String {
        let format = localizedString(key, language: language)
        guard !arguments.isEmpty else { return format }
        return String(format: format, locale: Locale(identifier: language.localeIdentifier), arguments: arguments)
    }

    nonisolated static func localizedString(_ key: String, language: AppLanguage = .persisted) -> String {
        let english = value(for: key, languageCode: AppLanguage.english.rawValue)
        let safeEnglish = english == key ? humanReadableFallback(for: key) : english
        guard language != .english else { return safeEnglish }
        let translated = value(for: key, languageCode: language.rawValue)
        return translated == key ? safeEnglish : translated
    }

    nonisolated private static func value(for key: String, languageCode: String) -> String {
        guard let path = Bundle.main.path(forResource: languageCode, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return key }
        return bundle.localizedString(forKey: key, value: nil, table: nil)
    }

    nonisolated private static func humanReadableFallback(for key: String) -> String {
        let finalComponent = key.split(separator: ".").last.map(String.init) ?? key
        return finalComponent.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

private extension LanguagePreference {
    var resolvedLanguage: AppLanguage {
        switch self {
        case .system: return LanguageStore.systemLanguage
        case .english: return .english
        case .german: return .german
        }
    }
}
