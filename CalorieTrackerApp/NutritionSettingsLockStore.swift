import CryptoKit
import Foundation
import Security

enum NutritionSettingsLockScope: String, CaseIterable, Identifiable {
    case dailyCalorieGoal
    case calorieBalance
    case calorieLimitBuffer
    case fastingBlock
    case trackingWindow
    case eveningRule

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .dailyCalorieGoal: "nutrition_lock.daily_calorie_goal"
        case .calorieBalance: "nutrition_lock.calorie_balance"
        case .calorieLimitBuffer: "nutrition_lock.calorie_limit_buffer"
        case .fastingBlock: "nutrition_lock.fasting_block"
        case .trackingWindow: "nutrition_lock.tracking_window"
        case .eveningRule: "nutrition_lock.evening_rule"
        }
    }
}

enum NutritionSettingsLockStore {
    private static let defaultsKey = "nutritionSettingsLockScopes_v1"
    private static let service = "com.hyse.HyseApp.nutrition-settings-lock"
    private static let account = "passcode-verifier"

    private struct Verifier: Codable {
        let salt: Data
        let digest: Data
    }

    static var hasPasscode: Bool {
        loadVerifier() != nil
    }

    static var enabledScopes: Set<NutritionSettingsLockScope> {
        let values = UserDefaults.standard.stringArray(forKey: defaultsKey) ?? []
        return Set(values.compactMap(NutritionSettingsLockScope.init(rawValue:)))
    }

    static func setEnabled(_ enabled: Bool, for scope: NutritionSettingsLockScope) {
        var scopes = enabledScopes
        if enabled {
            scopes.insert(scope)
        } else {
            scopes.remove(scope)
        }
        UserDefaults.standard.set(scopes.map(\.rawValue).sorted(), forKey: defaultsKey)
    }

    static func setPasscode(_ passcode: String) throws {
        guard isValid(passcode) else { throw NutritionSettingsLockError.invalidPasscode }
        var saltBytes = [UInt8](repeating: 0, count: 16)
        guard SecRandomCopyBytes(kSecRandomDefault, saltBytes.count, &saltBytes) == errSecSuccess else {
            throw NutritionSettingsLockError.secureStorageFailed
        }
        let salt = Data(saltBytes)
        let verifier = Verifier(salt: salt, digest: digest(passcode: passcode, salt: salt))
        let encoded = try JSONEncoder().encode(verifier)
        try saveVerifier(encoded)
    }

    static func verify(_ passcode: String) -> Bool {
        guard let verifier = loadVerifier() else { return false }
        let candidate = digest(passcode: passcode, salt: verifier.salt)
        guard candidate.count == verifier.digest.count else { return false }
        return zip(candidate, verifier.digest).reduce(UInt8(0)) { result, pair in
            result | (pair.0 ^ pair.1)
        } == 0
    }

    static func removePasscode() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }

    static func isValid(_ passcode: String) -> Bool {
        (4...8).contains(passcode.count) && passcode.allSatisfy(\.isNumber)
    }

    private static func digest(passcode: String, salt: Data) -> Data {
        var input = salt
        input.append(Data(passcode.utf8))
        return Data(SHA256.hash(data: input))
    }

    private static func loadVerifier() -> Verifier? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(Verifier.self, from: data)
    }

    private static func saveVerifier(_ data: Data) throws {
        let lookup: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let status = SecItemUpdate(lookup as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = lookup
            attributes.forEach { item[$0.key] = $0.value }
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else {
                throw NutritionSettingsLockError.secureStorageFailed
            }
        } else if status != errSecSuccess {
            throw NutritionSettingsLockError.secureStorageFailed
        }
    }
}

enum NutritionSettingsLockError: Error {
    case invalidPasscode
    case secureStorageFailed
}
