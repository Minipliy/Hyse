import Foundation

/// Server and app-group values come from `Hyse.xcconfig` via the
/// app's and widget's Info.plist, so a self-hosted build changes them in one
/// place instead of in the source code.
nonisolated enum HyseConfiguration {
    static let serverHost: String = infoValue("HyseServerHost") ?? "localhost"
    static let serverURL = "https://\(serverHost)"
    static let appGroup: String = infoValue("HyseAppGroup") ?? "group.com.example.hyse"
    static let contactEmail: String = infoValue("HyseContactEmail") ?? "support@example.com"

    private static func infoValue(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty, !value.hasPrefix("$(") else { return nil }
        return value
    }
}
