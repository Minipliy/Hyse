import Foundation
import OSLog
import UIKit

actor TrainingSyncService {
    static let shared = TrainingSyncService()
    private let baseURL = HyseConfiguration.serverURL
    private let logger = Logger(subsystem: "com.hyse.HyseApp", category: "TrainingSync")

    struct Result: Sendable {
        let workouts: [WorkoutLog]
        let routines: [WorkoutRoutine]
        let customExercises: [TrainingExercise]
        let favoriteExerciseIDs: Set<UUID>
        let serverStreak: TrainingServerStreak?
        let didFetch: Bool
        let didPush: Bool
    }

    private struct Page<T: Decodable>: Decodable { let page: Int; let totalPages: Int; let items: [T] }
    private struct RootRecord<T: Codable>: Codable {
        let id: String
        let clientID: String
        let snapshot: T?
        let media: String?
        enum CodingKeys: String, CodingKey { case id, media; case clientID = "client_id"; case snapshot = "snapshot_json" }
    }
    private struct IDRecord: Decodable {
        let id: String
        let clientID: String?
        enum CodingKeys: String, CodingKey { case id; case clientID = "client_id" }
    }
    private struct FavoriteRecord: Decodable { let id: String; let exerciseClientID: String; enum CodingKeys: String, CodingKey { case id; case exerciseClientID = "exercise_client_id" } }
    private struct APIErrorResponse: Decodable {
        struct FieldError: Decodable { let message: String? }
        let message: String?
        let data: [String: FieldError]?
    }

    func sync(workouts: [WorkoutLog], routines: [WorkoutRoutine], customExercises: [TrainingExercise], favoriteOverrides: [UUID: Bool], dirtyWorkoutIDs: Set<UUID>, dirtyRoutineIDs: Set<UUID>, deletedWorkoutIDs: Set<UUID>, deletedRoutineIDs: Set<UUID>, userID: String, token: String) async -> Result {
        guard !userID.isEmpty, !token.isEmpty else { return Result(workouts: [], routines: [], customExercises: [], favoriteExerciseIDs: [], serverStreak: nil, didFetch: false, didPush: false) }
        let deletedWorkoutsSynced = await deleteRoots(collection: "workouts", clientIDs: deletedWorkoutIDs, token: token)
        let deletedRoutinesSynced = await deleteRoots(collection: "workout_routines", clientIDs: deletedRoutineIDs, token: token)

        guard let remoteWorkoutRecords: [RootRecord<WorkoutLog>] = await fetchAll("workouts", token: token),
              let remoteRoutineRecords: [RootRecord<WorkoutRoutine>] = await fetchAll("workout_routines", token: token),
              let remoteExerciseRecords: [RootRecord<TrainingExercise>] = await fetchAll("exercises", token: token, filter: "is_custom = true"),
              let remoteFavorites: [FavoriteRecord] = await fetchAll("exercise_favorites", token: token) else {
            return Result(workouts: [], routines: [], customExercises: [], favoriteExerciseIDs: [], serverStreak: nil, didFetch: false, didPush: false)
        }
        let remoteStreaks: [TrainingServerStreak] = await fetchAll("training_streaks", token: token) ?? []

        var mergedWorkoutsByID = Dictionary(uniqueKeysWithValues: mergeLatest(local: workouts, remote: remoteWorkoutRecords.compactMap(\.snapshot), id: \.id, updatedAt: \.updatedAt).map { ($0.id, $0) })
        let localWorkoutsByID = Dictionary(uniqueKeysWithValues: workouts.map { ($0.id, $0) })
        // The dirty marker proves that this device has an unsent edit. A
        // remote timestamp can be newer because of clock skew or rounding.
        for id in dirtyWorkoutIDs {
            if let local = localWorkoutsByID[id] { mergedWorkoutsByID[id] = local }
        }
        let mergedWorkouts = Array(mergedWorkoutsByID.values)
        var mergedRoutinesByID = Dictionary(uniqueKeysWithValues: mergeLatest(local: routines, remote: remoteRoutineRecords.compactMap(\.snapshot), id: \.id, updatedAt: \.updatedAt).map { ($0.id, $0) })
        let localRoutinesByID = Dictionary(uniqueKeysWithValues: routines.map { ($0.id, $0) })
        // A dirty marker is stronger evidence than timestamps. Server and
        // device dates can be equal after JSON round-trips or skewed by a few
        // seconds; using the remote snapshot in that case silently drops new
        // routine exercises and sets before child sync begins.
        for id in dirtyRoutineIDs {
            if let local = localRoutinesByID[id] { mergedRoutinesByID[id] = local }
        }
        let mergedRoutines = Array(mergedRoutinesByID.values)
        let mergedExercises = mergeLatest(
            local: customExercises.filter { !TrainingExercise.isRetiredImported($0) },
            remote: remoteExerciseRecords.compactMap(\.snapshot).filter { !TrainingExercise.isRetiredImported($0) },
            id: \.id,
            updatedAt: \.updatedAt
        )
        let remoteExercisesByID = recordsByClientID(remoteExerciseRecords)
        let remoteWorkoutsByID = recordsByClientID(remoteWorkoutRecords)

        var didPush = deletedWorkoutsSynced && deletedRoutinesSynced
        for exercise in mergedExercises where shouldPush(exercise.updatedAt, remote: remoteExercisesByID[exercise.id]?.snapshot?.updatedAt) {
            var payload = exercisePayload(exercise); payload["created_by"] = userID
            if await upsert(collection: "exercises", clientID: exercise.id, userID: userID, token: token, payload: payload) == nil { didPush = false }
        }
        for routine in mergedRoutines where dirtyRoutineIDs.contains(routine.id) {
            let remoteID = await upsert(collection: "workout_routines", clientID: routine.id, userID: userID, token: token, payload: routinePayload(routine))
            if let remoteID {
                let childrenSynced = await syncRoutineChildren(routine, remoteRoutineID: remoteID, userID: userID, token: token)
                if !childrenSynced { didPush = false }
            } else { didPush = false }
        }
        for workout in mergedWorkouts where dirtyWorkoutIDs.contains(workout.id) {
            let remoteID = await upsert(collection: "workouts", clientID: workout.id, userID: userID, token: token, payload: workoutPayload(workout))
            if let remoteID {
                let mediaSynced = await uploadWorkoutMedia(workout, remoteID: remoteID, token: token)
                let childrenSynced = await syncChildren(workout, remoteWorkoutID: remoteID, userID: userID, token: token)
                if !mediaSynced || !childrenSynced { didPush = false }
            } else { didPush = false }
        }
        for workout in mergedWorkouts where !dirtyWorkoutIDs.contains(workout.id) && workout.mediaLocalFilename != nil {
            guard let remote = remoteWorkoutsByID[workout.id], remote.media?.isEmpty != false else { continue }
            if !(await uploadWorkoutMedia(workout, remoteID: remote.id, token: token)) { didPush = false }
        }
        var desiredFavorites = Set(remoteFavorites.compactMap { UUID(uuidString: $0.exerciseClientID) })
        for (id, isFavorite) in favoriteOverrides {
            if isFavorite { desiredFavorites.insert(id) } else { desiredFavorites.remove(id) }
        }
        let favoritesSynced = await syncFavorites(desiredFavorites, current: remoteFavorites, userID: userID, token: token)
        if !favoritesSynced { didPush = false }
        return Result(
            workouts: mergedWorkouts,
            routines: mergedRoutines,
            customExercises: mergedExercises,
            favoriteExerciseIDs: desiredFavorites,
            serverStreak: remoteStreaks.first,
            didFetch: true,
            didPush: didPush
        )
    }

    private func mergeLatest<T>(local: [T], remote: [T], id: KeyPath<T, UUID>, updatedAt: KeyPath<T, Date>) -> [T] {
        var values = Dictionary(uniqueKeysWithValues: remote.map { ($0[keyPath: id], $0) })
        for value in local {
            let key = value[keyPath: id]
            if value[keyPath: updatedAt] >= (values[key]?[keyPath: updatedAt] ?? .distantPast) { values[key] = value }
        }
        return Array(values.values)
    }

    private func recordsByClientID<T>(_ records: [RootRecord<T>]) -> [UUID: RootRecord<T>] {
        records.reduce(into: [:]) { values, record in
            if let id = UUID(uuidString: record.clientID) { values[id] = record }
        }
    }

    private func shouldPush(_ local: Date, remote: Date?) -> Bool {
        guard let remote else { return true }
        return local > remote
    }

    private func workoutPayload(_ workout: WorkoutLog) -> [String: Any] {
        var payload: [String: Any] = [
            "name": workout.name, "status": workout.status.rawValue,
            "started_at": Self.dateString(workout.startedAt), "timezone": workout.timezone,
            "notes": workout.notes, "duration": Int(workout.duration), "total_volume": workout.totalVolume,
            "visibility": workout.visibility ?? "private", "client_updated_at": Self.dateString(workout.updatedAt), "snapshot_json": jsonObject(workout)
        ]
        if let completedAt = workout.completedAt { payload["completed_at"] = Self.dateString(completedAt) }
        return payload
    }

    private func uploadWorkoutMedia(_ workout: WorkoutLog, remoteID: String, token: String) async -> Bool {
        guard let filename = workout.mediaLocalFilename, !filename.isEmpty else { return true }
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return false }
        let localURL = support.appendingPathComponent("HyseWorkoutMedia", isDirectory: true).appendingPathComponent(filename)
        // A synced workout can belong to another device. Keep its server file
        // when this device does not have the original local copy.
        guard FileManager.default.fileExists(atPath: localURL.path) else { return true }
        guard let sourceData = try? Data(contentsOf: localURL), !sourceData.isEmpty else { return false }
        let ext = localURL.pathExtension.lowercased()
        let data: Data
        let uploadName: String
        let mimeType: String
        if ["jpg", "jpeg"].contains(ext), sourceData.count <= 1_200_000 {
            // New workout photos are already resized and compressed before
            // local storage. Upload the same bytes instead of recompressing.
            data = sourceData
            uploadName = "workout.jpg"
            mimeType = "image/jpeg"
        } else if let image = UIImage(data: sourceData) {
            let maximumSide: CGFloat = 2048
            let scale = min(1, maximumSide / max(image.size.width, image.size.height))
            let size = CGSize(width: max(1, image.size.width * scale), height: max(1, image.size.height * scale))
            let normalized = UIGraphicsImageRenderer(size: size).image { _ in
                image.draw(in: CGRect(origin: .zero, size: size))
            }
            guard let jpeg = normalized.jpegData(compressionQuality: 0.8) else { return false }
            data = jpeg
            uploadName = "workout.jpg"
            mimeType = "image/jpeg"
        } else {
            data = sourceData
            uploadName = ext == "mp4" ? "workout.mp4" : "workout.mov"
            switch ext {
            case "mp4": mimeType = "video/mp4"
            case "mov": mimeType = "video/quicktime"
            default: return false
            }
        }
        guard data.count <= 15_728_640 else { return false }
        guard let url = URL(string: "\(baseURL)/api/collections/workouts/records/\(remoteID)") else { return false }
        let boundary = "HyseWorkout-\(UUID().uuidString)"
        var body = Data()
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"media\"; filename=\"\(uploadName)\"\r\nContent-Type: \(mimeType)\r\n\r\n".utf8))
        body.append(data)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.timeoutInterval = 60
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        do {
            let (responseData, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200...299).contains(status) else {
                logger.error("Workout media upload rejected: \(status) \(self.errorSummary(responseData), privacy: .public)")
                return false
            }
            return true
        } catch {
            logger.error("Workout media upload failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func routinePayload(_ routine: WorkoutRoutine) -> [String: Any] {
        var payload: [String: Any] = ["name": routine.name, "description": routine.details, "folder": routine.folder, "visibility": "private", "client_updated_at": Self.dateString(routine.updatedAt), "snapshot_json": jsonObject(routine)]
        // PocketBase number fields use zero for an unset optional weekday.
        payload["planned_weekday"] = routine.plannedWeekday ?? 0
        return payload
    }

    private func exercisePayload(_ exercise: TrainingExercise) -> [String: Any] {
        ["name_key": exercise.nameKey, "english_name": exercise.englishName, "german_name": exercise.germanName, "exercise_type": exercise.type.rawValue, "equipment": exercise.equipment.rawValue, "primary_muscles": exercise.primaryMuscles, "secondary_muscles": exercise.secondaryMuscles, "is_custom": exercise.isCustom, "visibility": "private", "moderation_status": "private", "client_updated_at": Self.dateString(exercise.updatedAt), "snapshot_json": jsonObject(exercise)]
    }

    private func syncChildren(_ workout: WorkoutLog, remoteWorkoutID: String, userID: String, token: String) async -> Bool {
        var succeeded = true
        let expectedExerciseIDs = Set(workout.exercises.map(\.id))
        guard let existing: [ChildRecord] = await fetchAll("workout_exercises", token: token, filter: "workout = \"\(remoteWorkoutID)\"") else { return false }
        for record in existing where !expectedExerciseIDs.contains(UUID(uuidString: record.clientID) ?? UUID()) {
            let deleted = await delete(collection: "workout_exercises", id: record.id, token: token)
            if !deleted { succeeded = false }
        }

        for (position, exercise) in workout.exercises.enumerated() {
            let payload: [String: Any] = [
                "workout": remoteWorkoutID, "position": position, "exercise_client_id": exercise.exerciseID.uuidString.lowercased(),
                "exercise_name_snapshot": exercise.exerciseNameSnapshot, "exercise_name_de_snapshot": exercise.exerciseGermanNameSnapshot,
                "exercise_type_snapshot": exercise.exerciseTypeSnapshot.rawValue, "equipment_snapshot": exercise.equipmentSnapshot.rawValue,
                "primary_muscles_snapshot": exercise.primaryMusclesSnapshot, "secondary_muscles_snapshot": exercise.secondaryMusclesSnapshot,
                "notes": exercise.notes, "rest_seconds": exercise.restSeconds, "superset_group": exercise.supersetGroup ?? ""
            ]
            guard let remoteExerciseID = await upsert(collection: "workout_exercises", clientID: exercise.id, userID: userID, token: token, payload: payload) else { succeeded = false; continue }
            let expectedSetIDs = Set(exercise.sets.map(\.id))
            guard let remoteSets: [ChildRecord] = await fetchAll("workout_sets", token: token, filter: "workout_exercise = \"\(remoteExerciseID)\"") else { succeeded = false; continue }
            for record in remoteSets where !expectedSetIDs.contains(UUID(uuidString: record.clientID) ?? UUID()) {
                let deleted = await delete(collection: "workout_sets", id: record.id, token: token)
                if !deleted { succeeded = false }
            }
            for (setPosition, set) in exercise.sets.enumerated() {
                var setPayload: [String: Any] = [
                    "workout_exercise": remoteExerciseID, "position": setPosition, "set_type": set.type.rawValue,
                    "weight": set.weightKilograms, "reps": set.reps, "duration": set.durationSeconds, "distance": set.distanceMeters,
                    "assisted_weight": set.assistedKilograms, "completed": set.completed, "volume": set.volume,
                    "personal_record_flags": set.personalRecordFlags
                ]
                if let rpe = set.rpe { setPayload["rpe"] = rpe }
                if let completedAt = set.completedAt { setPayload["completed_at"] = Self.dateString(completedAt) }
                if await upsert(collection: "workout_sets", clientID: set.id, userID: userID, token: token, payload: setPayload) == nil { succeeded = false }
            }
        }
        return succeeded
    }

    private func syncRoutineChildren(_ routine: WorkoutRoutine, remoteRoutineID: String, userID: String, token: String) async -> Bool {
        var succeeded = true
        let expectedExerciseIDs = Set(routine.exercises.map(\.id))
        guard let existing: [ChildRecord] = await fetchAll("routine_exercises", token: token, filter: "routine = \"\(remoteRoutineID)\"") else { return false }
        for record in existing where !expectedExerciseIDs.contains(UUID(uuidString: record.clientID) ?? UUID()) {
            let deleted = await delete(collection: "routine_exercises", id: record.id, token: token)
            if !deleted { succeeded = false }
        }
        for (position, exercise) in routine.exercises.enumerated() {
            let payload: [String: Any] = [
                "routine": remoteRoutineID, "exercise_client_id": exercise.exercise.id.uuidString.lowercased(),
                "position": position, "notes": exercise.notes, "rest_seconds": exercise.restSeconds,
                "superset_group": exercise.supersetGroup ?? ""
            ]
            guard let remoteExerciseID = await upsert(collection: "routine_exercises", clientID: exercise.id, userID: userID, token: token, payload: payload) else { succeeded = false; continue }
            let expectedSetIDs = Set(exercise.sets.map(\.id))
            guard let remoteSets: [ChildRecord] = await fetchAll("routine_sets", token: token, filter: "routine_exercise = \"\(remoteExerciseID)\"") else { succeeded = false; continue }
            for record in remoteSets where !expectedSetIDs.contains(UUID(uuidString: record.clientID) ?? UUID()) {
                let deleted = await delete(collection: "routine_sets", id: record.id, token: token)
                if !deleted { succeeded = false }
            }
            for (setPosition, set) in exercise.sets.enumerated() {
                var setPayload: [String: Any] = [
                    "routine_exercise": remoteExerciseID, "position": setPosition, "set_type": set.type.rawValue,
                    "target_weight": set.weightKilograms, "target_reps": set.reps,
                    "target_duration": set.durationSeconds, "target_distance": set.distanceMeters
                ]
                if let rpe = set.rpe { setPayload["target_rpe"] = rpe }
                if await upsert(collection: "routine_sets", clientID: set.id, userID: userID, token: token, payload: setPayload) == nil { succeeded = false }
            }
        }
        return succeeded
    }

    private func deleteRoots(collection: String, clientIDs: Set<UUID>, token: String) async -> Bool {
        var succeeded = true
        for clientID in clientIDs {
            let value = clientID.uuidString.lowercased()
            guard let records: [IDRecord] = await fetchAll(collection, token: token, filter: "client_id = \"\(value)\"") else { succeeded = false; continue }
            for record in records {
                let deleted = await delete(collection: collection, id: record.id, token: token)
                if !deleted { succeeded = false }
            }
        }
        return succeeded
    }

    private struct ChildRecord: Decodable { let id: String; let clientID: String; enum CodingKeys: String, CodingKey { case id; case clientID = "client_id" } }

    private func syncFavorites(_ desired: Set<UUID>, current: [FavoriteRecord], userID: String, token: String) async -> Bool {
        var succeeded = true
        let currentIDs = Set(current.compactMap { UUID(uuidString: $0.exerciseClientID) })
        for record in current where !desired.contains(UUID(uuidString: record.exerciseClientID) ?? UUID()) {
            let deleted = await delete(collection: "exercise_favorites", id: record.id, token: token)
            if !deleted { succeeded = false }
        }
        for id in desired.subtracting(currentIDs) {
            if await create(collection: "exercise_favorites", token: token, payload: ["user": userID, "exercise_client_id": id.uuidString.lowercased()]) == nil { succeeded = false }
        }
        return succeeded
    }

    private func upsert(collection: String, clientID: UUID, userID: String, token: String, payload: [String: Any]) async -> String? {
        let value = clientID.uuidString.lowercased()
        let existing: [IDRecord]? = await fetchAll(collection, token: token, filter: "client_id = \"\(value)\"")
        var body = payload; body["client_id"] = value
        if let id = existing?.first?.id { return await update(collection: collection, id: id, token: token, payload: body) ? id : nil }
        body["user"] = userID
        return await create(collection: collection, token: token, payload: body)
    }

    private func fetchAll<T: Decodable>(_ collection: String, token: String, filter: String? = nil) async -> [T]? {
        var page = 1
        var values: [T] = []

        while true {
            var components = URLComponents(string: "\(baseURL)/api/collections/\(collection)/records")
            var items = [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "perPage", value: "200")
            ]
            if let filter { items.append(URLQueryItem(name: "filter", value: filter)) }
            components?.queryItems = items
            guard let url = components?.url else { return nil }
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                    logger.error("Fetch \(collection, privacy: .public) rejected: \((response as? HTTPURLResponse)?.statusCode ?? 0)")
                    return nil
                }
                let result = try JSONDecoder().decode(Page<T>.self, from: data)
                values.append(contentsOf: result.items)
                guard result.page < result.totalPages else { return values }
                page += 1
            } catch {
                logger.error("Fetch \(collection, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
    }

    private func create(collection: String, token: String, payload: [String: Any]) async -> String? {
        guard let url = URL(string: "\(baseURL)/api/collections/\(collection)/records") else { return nil }
        let request = request(url: url, method: "POST", token: token, payload: payload)
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                logger.error("Create \(collection, privacy: .public) rejected: \((response as? HTTPURLResponse)?.statusCode ?? 0) \(self.errorSummary(data), privacy: .public)")
                return nil
            }
            return try JSONDecoder().decode(IDRecord.self, from: data).id
        } catch {
            logger.error("Create \(collection, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func update(collection: String, id: String, token: String, payload: [String: Any]) async -> Bool {
        guard let url = URL(string: "\(baseURL)/api/collections/\(collection)/records/\(id)") else { return false }
        let request = request(url: url, method: "PATCH", token: token, payload: payload)
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200...299).contains(status) else {
                logger.error("Update \(collection, privacy: .public) rejected: \(status) \(self.errorSummary(data), privacy: .public)")
                return false
            }
            return true
        } catch {
            logger.error("Update \(collection, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func errorSummary(_ data: Data) -> String {
        guard let response = try? JSONDecoder().decode(APIErrorResponse.self, from: data) else { return "" }
        let fields = response.data?
            .sorted(by: { $0.key < $1.key })
            .map { key, value in value.message.map { "\(key): \($0)" } ?? key }
            .joined(separator: ", ")
        return [response.message, fields].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " — ")
    }

    private func delete(collection: String, id: String, token: String) async -> Bool {
        guard let url = URL(string: "\(baseURL)/api/collections/\(collection)/records/\(id)") else { return false }
        var request = URLRequest(url: url); request.httpMethod = "DELETE"; request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        do { let (_, response) = try await URLSession.shared.data(for: request); return (200...299).contains((response as? HTTPURLResponse)?.statusCode ?? 0) } catch { return false }
    }

    private func request(url: URL, method: String, token: String, payload: [String: Any]) -> URLRequest {
        var request = URLRequest(url: url); request.httpMethod = method; request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization"); request.httpBody = try? JSONSerialization.data(withJSONObject: payload); return request
    }

    private func jsonObject<T: Encodable>(_ value: T) -> Any {
        guard let data = try? JSONEncoder().encode(value), let object = try? JSONSerialization.jsonObject(with: data) else { return [:] }
        return object
    }

    nonisolated private static func dateString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return formatter.string(from: date)
    }
}
