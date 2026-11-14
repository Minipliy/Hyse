import Foundation
import OSLog

actor DailyFoodScheduleSyncService {
    static let shared = DailyFoodScheduleSyncService()

    struct Result: Sendable {
        let schedules: [DailyFoodSchedule]
        let uploadedIDs: Set<UUID>
        let deletedIDs: Set<UUID>
        let didFetch: Bool
    }

    private struct RemoteSchedule: Decodable, Sendable {
        let id: String
        let clientID: String
        let snapshot: DailyFoodSchedule?

        enum CodingKeys: String, CodingKey {
            case id
            case clientID = "client_id"
            case snapshot = "snapshot_json"
        }
    }

    private struct Page: Decodable, Sendable {
        let page: Int
        let totalPages: Int
        let items: [RemoteSchedule]
    }

    private let baseURL = HyseConfiguration.serverURL
    private let logger = Logger(subsystem: "com.hyse.HyseApp", category: "DailyFoodSync")

    func sync(
        schedules: [DailyFoodSchedule],
        dirtyIDs: Set<UUID>,
        deletedIDs: Set<UUID>,
        userID: String,
        token: String
    ) async -> Result {
        guard !userID.isEmpty, !token.isEmpty, let fetched = await fetchAll(token: token) else {
            return Result(schedules: [], uploadedIDs: [], deletedIDs: [], didFetch: false)
        }

        var remoteByClientID = Dictionary(uniqueKeysWithValues: fetched.compactMap { remote in
            UUID(uuidString: remote.clientID).map { ($0, remote) }
        })
        var successfulDeletes = Set<UUID>()
        for id in deletedIDs {
            guard let remote = remoteByClientID[id] else {
                successfulDeletes.insert(id)
                continue
            }
            if await delete(remoteID: remote.id, token: token) {
                successfulDeletes.insert(id)
                remoteByClientID.removeValue(forKey: id)
            }
        }

        let localByID = Dictionary(uniqueKeysWithValues: schedules.map { ($0.id, $0) })
        var successfulUploads = Set<UUID>()
        for id in dirtyIDs where !deletedIDs.contains(id) {
            guard let schedule = localByID[id] else { continue }
            let remoteID = remoteByClientID[id]?.id
            if let saved = await send(schedule, remoteID: remoteID, userID: userID, token: token),
               saved.snapshot != nil {
                remoteByClientID[id] = saved
                successfulUploads.insert(id)
            }
        }

        return Result(
            schedules: remoteByClientID.values.compactMap(\.snapshot),
            uploadedIDs: successfulUploads,
            deletedIDs: successfulDeletes,
            didFetch: true
        )
    }

    private func fetchAll(token: String) async -> [RemoteSchedule]? {
        var page = 1
        var result: [RemoteSchedule] = []
        while true {
            var components = URLComponents(string: "\(baseURL)/api/collections/daily_food_schedules/records")
            components?.queryItems = [
                URLQueryItem(name: "page", value: "\(page)"),
                URLQueryItem(name: "perPage", value: "100"),
                URLQueryItem(name: "sort", value: "created")
            ]
            guard let url = components?.url else { return nil }
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard (200...299).contains(status) else {
                    logger.error("Daily-food fetch rejected with status \(status)")
                    return nil
                }
                let value = try JSONDecoder().decode(Page.self, from: data)
                result.append(contentsOf: value.items)
                if value.page >= value.totalPages { return result }
                page += 1
            } catch {
                logger.error("Daily-food fetch failed: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
    }

    private func send(
        _ schedule: DailyFoodSchedule,
        remoteID: String?,
        userID: String,
        token: String
    ) async -> RemoteSchedule? {
        let endpoint = remoteID.map { "/records/\($0)" } ?? "/records"
        guard let url = URL(string: "\(baseURL)/api/collections/daily_food_schedules\(endpoint)"),
              let snapshotData = try? JSONEncoder().encode(schedule),
              let snapshot = try? JSONSerialization.jsonObject(with: snapshotData) else { return nil }
        var payload: [String: Any] = [
            "client_id": schedule.id.uuidString.lowercased(),
            "snapshot_json": snapshot,
            "updated_at_local": ISO8601DateFormatter().string(from: schedule.modificationDate)
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
            guard (200...299).contains(status) else {
                logger.error("Daily-food upload rejected with status \(status)")
                return nil
            }
            return try JSONDecoder().decode(RemoteSchedule.self, from: data)
        } catch {
            logger.error("Daily-food upload failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func delete(remoteID: String, token: String) async -> Bool {
        guard let url = URL(string: "\(baseURL)/api/collections/daily_food_schedules/records/\(remoteID)") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (200...299).contains((response as? HTTPURLResponse)?.statusCode ?? 0)
        } catch {
            logger.error("Daily-food delete failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
