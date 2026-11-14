import Foundation
import OSLog

actor StreakRewardsSyncService {
    static let shared = StreakRewardsSyncService()

    struct Result: Sendable {
        let state: StreakRewardsState?
        let updatedAt: Date
        let didSync: Bool
    }

    private struct RemoteState: Decodable, Sendable {
        let id: String
        let snapshot: StreakRewardsState
        let updatedAtLocal: String

        enum CodingKeys: String, CodingKey {
            case id
            case snapshot = "snapshot_json"
            case updatedAtLocal = "updated_at_local"
        }
    }

    private struct Page: Decodable, Sendable {
        let items: [RemoteState]
    }

    private struct FetchResult: Sendable {
        let state: RemoteState?
        let succeeded: Bool
    }

    private let baseURL = HyseConfiguration.serverURL
    private let logger = Logger(subsystem: "com.hyse.HyseApp", category: "StreakRewardsSync")

    func sync(
        localState: StreakRewardsState,
        localUpdatedAt: Date,
        mergeFirstLocalActions: Bool,
        userID: String,
        token: String
    ) async -> Result {
        guard !userID.isEmpty, !token.isEmpty else {
            return Result(state: nil, updatedAt: localUpdatedAt, didSync: false)
        }
        let fetched = await fetch(token: token)
        guard fetched.succeeded else {
            return Result(state: nil, updatedAt: localUpdatedAt, didSync: false)
        }

        guard let remoteState = fetched.state else {
            return await save(
                state: localState,
                updatedAt: max(localUpdatedAt, Date()),
                remoteID: nil,
                userID: userID,
                token: token
            )
        }

        if mergeFirstLocalActions {
            let merged = localState.mergingFirstLocalActions(into: remoteState.snapshot)
            if merged == remoteState.snapshot {
                return Result(
                    state: remoteState.snapshot,
                    updatedAt: Self.date(from: remoteState.updatedAtLocal) ?? .distantPast,
                    didSync: true
                )
            }
            return await save(
                state: merged,
                updatedAt: max(localUpdatedAt, Date()),
                remoteID: remoteState.id,
                userID: userID,
                token: token
            )
        }

        let remoteUpdatedAt = Self.date(from: remoteState.updatedAtLocal) ?? .distantPast
        guard localUpdatedAt > remoteUpdatedAt else {
            return Result(state: remoteState.snapshot, updatedAt: remoteUpdatedAt, didSync: true)
        }
        return await save(
            state: localState,
            updatedAt: localUpdatedAt,
            remoteID: remoteState.id,
            userID: userID,
            token: token
        )
    }

    private func fetch(token: String) async -> FetchResult {
        var components = URLComponents(string: "\(baseURL)/api/collections/streak_reward_states/records")
        components?.queryItems = [
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "perPage", value: "1")
        ]
        guard let url = components?.url else { return FetchResult(state: nil, succeeded: false) }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200...299).contains(status) else {
                logger.error("Streak-reward fetch rejected with status \(status)")
                return FetchResult(state: nil, succeeded: false)
            }
            return FetchResult(state: try JSONDecoder().decode(Page.self, from: data).items.first, succeeded: true)
        } catch {
            logger.error("Streak-reward fetch failed: \(error.localizedDescription, privacy: .public)")
            return FetchResult(state: nil, succeeded: false)
        }
    }

    private func save(
        state: StreakRewardsState,
        updatedAt: Date,
        remoteID: String?,
        userID: String,
        token: String
    ) async -> Result {
        let suffix = remoteID.map { "/records/\($0)" } ?? "/records"
        guard let url = URL(string: "\(baseURL)/api/collections/streak_reward_states\(suffix)"),
              let snapshotData = try? JSONEncoder().encode(state),
              let snapshot = try? JSONSerialization.jsonObject(with: snapshotData) else {
            return Result(state: nil, updatedAt: updatedAt, didSync: false)
        }
        var payload: [String: Any] = [
            "snapshot_json": snapshot,
            "updated_at_local": Self.string(from: updatedAt)
        ]
        if remoteID == nil { payload["user"] = userID }
        var request = URLRequest(url: url)
        request.httpMethod = remoteID == nil ? "POST" : "PATCH"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200...299).contains(status),
                  let saved = try? JSONDecoder().decode(RemoteState.self, from: data) else {
                logger.error("Streak-reward upload rejected with status \(status)")
                return Result(state: nil, updatedAt: updatedAt, didSync: false)
            }
            return Result(
                state: saved.snapshot,
                updatedAt: Self.date(from: saved.updatedAtLocal) ?? updatedAt,
                didSync: true
            )
        } catch {
            logger.error("Streak-reward upload failed: \(error.localizedDescription, privacy: .public)")
            return Result(state: nil, updatedAt: updatedAt, didSync: false)
        }
    }

    private static func string(from date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func date(from value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value) {
            return date
        }
        let pocketBaseFormatter = DateFormatter()
        pocketBaseFormatter.calendar = Calendar(identifier: .gregorian)
        pocketBaseFormatter.locale = Locale(identifier: "en_US_POSIX")
        pocketBaseFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        pocketBaseFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSX"
        return pocketBaseFormatter.date(from: value)
    }
}
