import Foundation
import Combine

nonisolated struct TrainingSocialUser: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let username: String
    let nickname: String?
    var avatar: String?
    var avatarURL: String?
    var state: String?
    var bio: String? = nil
    var website: String? = nil
    enum CodingKeys: String, CodingKey { case id, username, nickname, avatar, state, bio, website; case avatarURL = "avatar_url" }
    var displayName: String { let value = nickname?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""; return value.isEmpty ? username : value }
}

nonisolated struct TrainingFriendConnection: Codable, Identifiable, Hashable, Sendable {
    let relationshipID: String
    let userID: String
    let username: String
    let nickname: String?
    var avatar: String?
    var avatarURL: String?
    var id: String { relationshipID }
    enum CodingKeys: String, CodingKey {
        case relationshipID = "relationship_id", userID = "user_id", username, nickname, avatar
        case avatarURL = "avatar_url"
    }
    var displayName: String { let value = nickname?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""; return value.isEmpty ? username : value }
    var profileUser: TrainingSocialUser {
        TrainingSocialUser(id: userID, username: username, nickname: nickname, avatar: avatar, avatarURL: avatarURL, state: "friends")
    }
}

nonisolated struct FriendWorkout: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let clientID: String?
    let userID: String?
    let username: String
    let nickname: String?
    var avatar: String?
    var avatarURL: String?
    var name: String
    var notes: String
    var mediaURL: String?
    var completedAt: String
    var duration: Double
    var totalVolume: Double
    var exercisePreview: [TrainingPublicExercisePreview]
    var likeCount: Int
    var commentCount: Int
    var likedByMe: Bool
    enum CodingKeys: String, CodingKey {
        case id, username, nickname, name, notes, duration, avatar
        case clientID = "client_id"
        case mediaURL = "media_url"
        case avatarURL = "avatar_url"
        case userID = "user_id"
        case completedAt = "completed_at"
        case totalVolume = "total_volume"
        case exercisePreview = "exercise_preview"
        case likeCount = "like_count", commentCount = "comment_count", likedByMe = "liked_by_me"
    }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        clientID = try values.decodeIfPresent(String.self, forKey: .clientID)
        userID = try values.decodeIfPresent(String.self, forKey: .userID)
        username = try values.decode(String.self, forKey: .username)
        nickname = try values.decodeIfPresent(String.self, forKey: .nickname)
        avatar = try values.decodeIfPresent(String.self, forKey: .avatar)
        avatarURL = try values.decodeIfPresent(String.self, forKey: .avatarURL)
        name = try values.decode(String.self, forKey: .name)
        notes = try values.decodeIfPresent(String.self, forKey: .notes) ?? ""
        mediaURL = try values.decodeIfPresent(String.self, forKey: .mediaURL)
        completedAt = try values.decode(String.self, forKey: .completedAt)
        duration = try values.decodeIfPresent(Double.self, forKey: .duration) ?? 0
        totalVolume = try values.decodeIfPresent(Double.self, forKey: .totalVolume) ?? 0
        exercisePreview = try values.decodeIfPresent([TrainingPublicExercisePreview].self, forKey: .exercisePreview) ?? []
        likeCount = try values.decodeIfPresent(Int.self, forKey: .likeCount) ?? 0
        commentCount = try values.decodeIfPresent(Int.self, forKey: .commentCount) ?? 0
        likedByMe = try values.decodeIfPresent(Bool.self, forKey: .likedByMe) ?? false
    }
    var displayName: String { let value = nickname?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""; return value.isEmpty ? username : value }
    var date: Date? {
        // PocketBase returns date fields with a space instead of the ISO 8601
        // `T`. Without normalizing it, synced workouts sort to the very end
        // of the friends feed as soon as they replace the local entry.
        var value = completedAt
        if value.count > 10 {
            let separator = value.index(value.startIndex, offsetBy: 10)
            if value[separator] == " " { value.replaceSubrange(separator...separator, with: "T") }
        }
        return Self.formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
    private static let formatter: ISO8601DateFormatter = {
        let value = ISO8601DateFormatter(); value.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return value
    }()
}

nonisolated struct TrainingPublicExercisePreview: Codable, Hashable, Sendable {
    let name: String
    let germanName: String
    let setCount: Int
    enum CodingKeys: String, CodingKey {
        case name
        case germanName = "german_name", setCount = "set_count"
    }
}

nonisolated struct FriendWorkoutComment: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let userID: String
    let username: String
    let nickname: String?
    let avatar: String?
    let avatarURL: String?
    let body: String
    let replyToID: String?
    let created: String
    enum CodingKeys: String, CodingKey { case id, username, nickname, avatar, body, created; case userID = "user_id", avatarURL = "avatar_url", replyToID = "reply_to" }
    var displayName: String { let value = nickname?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""; return value.isEmpty ? username : value }
    var parentID: String? { guard let replyToID, !replyToID.isEmpty else { return nil }; return replyToID }
    var date: Date? { Self.fractionalFormatter.date(from: created) ?? ISO8601DateFormatter().date(from: created) }
    private static let fractionalFormatter: ISO8601DateFormatter = {
        let value = ISO8601DateFormatter()
        value.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return value
    }()
}

nonisolated struct FriendWorkoutLike: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let username: String
    let nickname: String?
    let avatar: String?
    let avatarURL: String?
    enum CodingKeys: String, CodingKey {
        case id, username, nickname, avatar
        case avatarURL = "avatar_url"
    }
    var displayName: String {
        let value = nickname?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? username : value
    }
}

nonisolated struct FriendWorkoutDetail: Codable, Hashable, Sendable {
    var workout: FriendWorkout
    var notes: String
    var snapshot: WorkoutLog?
    var comments: [FriendWorkoutComment]
    var likes: [FriendWorkoutLike]

    init(from decoder: Decoder) throws {
        workout = try FriendWorkout(from: decoder)
        let values = try decoder.container(keyedBy: CodingKeys.self)
        notes = try values.decodeIfPresent(String.self, forKey: .notes) ?? ""
        snapshot = (try? values.decodeIfPresent(WorkoutLog.self, forKey: .snapshot)) ?? nil
        comments = try values.decodeIfPresent([FriendWorkoutComment].self, forKey: .comments) ?? []
        likes = try values.decodeIfPresent([FriendWorkoutLike].self, forKey: .likes) ?? []
    }
    func encode(to encoder: Encoder) throws {
        try workout.encode(to: encoder)
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(notes, forKey: .notes)
        try values.encodeIfPresent(snapshot, forKey: .snapshot)
        try values.encode(comments, forKey: .comments)
        try values.encode(likes, forKey: .likes)
    }
    enum CodingKeys: String, CodingKey { case notes, snapshot, comments, likes }
}

nonisolated struct TrainingPublicProfile: Hashable, Sendable {
    var user: TrainingSocialUser
    let workouts: [FriendWorkout]
    let workoutCount: Int?
    let friendCount: Int?
    let routineCount: Int?
    let weeklyHours: [TrainingPublicWeek]
    let routines: [TrainingPublicRoutine]
}

nonisolated struct TrainingPublicWeek: Codable, Hashable, Sendable, Identifiable {
    let week: String
    let hours: Double
    var id: String { week }
    var date: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: week) ?? ISO8601DateFormatter().date(from: week)
    }
}

nonisolated struct TrainingPublicRoutine: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let name: String
}

nonisolated enum WorkoutShareLink {
    static let host = HyseConfiguration.serverHost

    static func url(workoutID: String, isGerman: Bool) -> URL {
        let encodedID = workoutID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? workoutID
        let path = isGerman ? "/de/training/\(encodedID)" : "/en/workout/\(encodedID)"
        return URL(string: "https://\(host)\(path)")!
    }

    static func workoutID(from url: URL) -> String? {
        let path = url.pathComponents.filter { $0 != "/" }
        let candidate: String?

        if url.scheme == "hyseapp", url.host == "workout" {
            candidate = path.first
        } else if url.scheme == "https", url.host == host,
                  path.count == 3,
                  (path[0] == "en" && path[1] == "workout") || (path[0] == "de" && path[1] == "training") {
            candidate = path[2]
        } else {
            candidate = nil
        }

        guard let candidate,
              !candidate.isEmpty,
              candidate.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-")).contains($0) }) else {
            return nil
        }
        return candidate
    }
}

actor TrainingSocialService {
    static let shared = TrainingSocialService()
    private let baseURL = HyseConfiguration.serverURL
    private struct Profile: Decodable { let id: String; let username: String; let nickname: String?; let bio: String?; let website: String? }
    private struct PublicDetailsResponse: Decodable { let bio: String; let website: String }
    private struct SearchResponse: Decodable { let items: [TrainingSocialUser] }
    private struct PublicProfileResponse: Decodable {
        let profile: TrainingSocialUser
        let workouts: [FriendWorkout]
        let workoutCount: Int?
        let friendCount: Int?
        let routineCount: Int?
        let weeklyHours: [TrainingPublicWeek]?
        let routines: [TrainingPublicRoutine]?
        enum CodingKeys: String, CodingKey {
            case profile, workouts, routines
            case workoutCount = "workout_count", friendCount = "friend_count", routineCount = "routine_count", weeklyHours = "weekly_hours"
        }
    }
    private struct ConnectionsResponse: Decodable { let friends: [TrainingFriendConnection]; let requests: [TrainingFriendConnection] }
    private struct FeedResponse: Decodable { let items: [FriendWorkout] }
    private struct LikeResponse: Decodable { let liked: Bool; let likeCount: Int; enum CodingKeys: String, CodingKey { case liked; case likeCount = "like_count" } }
    private struct CommentResponse: Decodable { let comment: FriendWorkoutComment; let commentCount: Int; enum CodingKeys: String, CodingKey { case comment; case commentCount = "comment_count" } }

    func load(token: String) async throws -> (username: String, nickname: String, bio: String?, website: String?, friends: [TrainingFriendConnection], requests: [TrainingFriendConnection], feed: [FriendWorkout]) {
        async let profile: Profile = get("/api/hyse/social/profile", token: token)
        async let connections: ConnectionsResponse = get("/api/hyse/social/connections", token: token)
        async let feed: FeedResponse = get("/api/hyse/social/feed", token: token)
        return try await (profile.username, profile.nickname ?? "", profile.bio, profile.website, connections.friends, connections.requests, feed.items)
    }

    func search(_ query: String, token: String) async throws -> [TrainingSocialUser] {
        guard var components = URLComponents(string: "\(baseURL)/api/hyse/social/search") else {
            throw TrainingSocialError.invalidURL
        }
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        guard let url = components.url else { throw TrainingSocialError.invalidURL }
        let response: SearchResponse = try await send(url: url, method: "GET", token: token, body: nil)
        return response.items
    }

    func publicProfile(_ userID: String, token: String) async throws -> TrainingPublicProfile {
        let response: PublicProfileResponse = try await get("/api/hyse/social/users/\(userID)", token: token)
        return TrainingPublicProfile(
            user: response.profile,
            workouts: response.workouts,
            workoutCount: response.workoutCount,
            friendCount: response.friendCount,
            routineCount: response.routineCount,
            weeklyHours: response.weeklyHours ?? [],
            routines: response.routines ?? []
        )
    }

    func updateUsername(_ username: String, token: String) async throws -> String {
        let response: Profile = try await post("/api/hyse/social/username", token: token, body: ["username": username])
        return response.username
    }

    func updateNickname(_ nickname: String, token: String) async throws -> String {
        let response: Profile = try await post("/api/hyse/social/nickname", token: token, body: ["nickname": nickname])
        return response.nickname ?? ""
    }

    func updatePublicDetails(bio: String, website: String, token: String) async throws -> (bio: String, website: String) {
        let response: PublicDetailsResponse = try await post(
            "/api/hyse/social/details", token: token, body: ["bio": bio, "website": website]
        )
        return (response.bio, response.website)
    }

    func requestFriend(_ userID: String, token: String) async throws {
        let _: ActionResponse = try await post("/api/hyse/social/request", token: token, body: ["user_id": userID])
    }

    func accept(_ relationshipID: String, token: String) async throws {
        let _: ActionResponse = try await post("/api/hyse/social/accept", token: token, body: ["relationship_id": relationshipID])
    }

    func remove(_ relationshipID: String, token: String) async throws {
        let _: ActionResponse = try await post("/api/hyse/social/remove", token: token, body: ["relationship_id": relationshipID])
    }

    func workoutDetail(_ id: String, token: String? = nil) async throws -> FriendWorkoutDetail {
        try await get("/api/hyse/social/workouts/\(id)", token: token)
    }

    func toggleLike(_ id: String, token: String) async throws -> (liked: Bool, count: Int) {
        let response: LikeResponse = try await post("/api/hyse/social/workouts/\(id)/like", token: token, body: [:])
        return (response.liked, response.likeCount)
    }

    func addComment(_ body: String, workoutID: String, replyToID: String? = nil, token: String) async throws -> (FriendWorkoutComment, Int) {
        var payload = ["body": body]
        if let replyToID { payload["reply_to"] = replyToID }
        let response: CommentResponse = try await post("/api/hyse/social/workouts/\(workoutID)/comments", token: token, body: payload)
        return (response.comment, response.commentCount)
    }

    private struct ActionResponse: Decodable {
        var status: String?; var relationshipID: String?; var removed: Bool?
        enum CodingKeys: String, CodingKey { case status, removed; case relationshipID = "relationship_id" }
    }

    private func get<T: Decodable>(_ path: String, token: String?) async throws -> T {
        guard let url = URL(string: baseURL + path) else { throw TrainingSocialError.invalidURL }
        return try await send(url: url, method: "GET", token: token, body: nil)
    }

    private func post<T: Decodable>(_ path: String, token: String, body: [String: String]) async throws -> T {
        guard let url = URL(string: baseURL + path) else { throw TrainingSocialError.invalidURL }
        return try await send(url: url, method: "POST", token: token, body: body)
    }

    private func send<T: Decodable>(url: URL, method: String, token: String?, body: [String: String]?) async throws -> T {
        var request = URLRequest(url: url); request.httpMethod = method
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body { request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.httpBody = try JSONEncoder().encode(body) }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["message"] as? String
            throw TrainingSocialError.server(message ?? "training.social.error")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

enum TrainingSocialError: LocalizedError {
    case server(String)
    case invalidURL
    var errorDescription: String? {
        switch self {
        case .server(let message): return message
        case .invalidURL: return LanguageStore.localizedString("training.social.error")
        }
    }
}

@MainActor
final class TrainingSocialStore: ObservableObject {
    @Published private(set) var username = ""
    @Published private(set) var nickname = ""
    @Published private(set) var bio = ""
    @Published private(set) var website = ""
    @Published private(set) var needsBioPublication = false
    @Published private(set) var friends: [TrainingFriendConnection] = []
    @Published private(set) var requests: [TrainingFriendConnection] = []
    @Published private(set) var feed: [FriendWorkout] = []
    @Published private(set) var searchResults: [TrainingSocialUser] = []
    @Published private(set) var isSearching = false
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var workoutDetails: [String: FriendWorkoutDetail] = [:]
    private var loadedAccountID: String?
    private var lastNetworkLoadAt: Date?
    private var activeLoadID: UUID?
    private var activeLoadAccountID: String?
    private var refreshAfterActiveLoad = false
    private var locallyDeletedWorkoutIDs: Set<String> = []
    private var searchRevision: UInt = 0
    private let networkFreshness: TimeInterval = 900

    private struct CachedState: Codable {
        let username: String
        let nickname: String?
        let friends: [TrainingFriendConnection]
        let requests: [TrainingFriendConnection]
        let feed: [FriendWorkout]
        let savedAt: Date
    }

    func load(auth: AuthManager, force: Bool = false) async {
        guard auth.isLoggedIn, !auth.token.isEmpty else {
            username = ""
            nickname = ""
            bio = ""
            website = ""
            needsBioPublication = false
            friends = []
            requests = []
            feed = []
            searchResults = []
            isSearching = false
            searchRevision &+= 1
            workoutDetails = [:]
            loadedAccountID = nil
            lastNetworkLoadAt = nil
            activeLoadID = nil
            activeLoadAccountID = nil
            refreshAfterActiveLoad = false
            isLoading = false
            errorMessage = nil
            return
        }
        let accountID = auth.accountID
        if loadedAccountID != accountID {
            loadedAccountID = accountID
            lastNetworkLoadAt = nil
            searchResults = []
            workoutDetails = [:]
            locallyDeletedWorkoutIDs = []
            username = ""
            nickname = ""
            bio = UserDefaults.standard.string(forKey: bioKey(accountID)) ?? ""
            website = ""
            needsBioPublication = false
            friends = []
            requests = []
            feed = []
            locallyDeletedWorkoutIDs = Set(UserDefaults.standard.stringArray(forKey: locallyDeletedWorkoutKey(accountID)) ?? [])
            restoreCache(accountID: accountID)
        }
        let accountUsername = auth.accountName.contains("@") ? "" : auth.accountName
        if !accountUsername.isEmpty { username = accountUsername }
        if !force, let lastNetworkLoadAt, Date().timeIntervalSince(lastNetworkLoadAt) < networkFreshness { return }
        if activeLoadAccountID == accountID {
            refreshAfterActiveLoad = refreshAfterActiveLoad || force
            return
        }
        let loadID = UUID()
        activeLoadID = loadID
        activeLoadAccountID = accountID
        refreshAfterActiveLoad = false
        let hasVisibleCache = !username.isEmpty || !friends.isEmpty || !requests.isEmpty || !feed.isEmpty
        isLoading = !hasVisibleCache
        errorMessage = nil
        var wasCancelled = false
        defer {
            if activeLoadID == loadID {
                activeLoadID = nil
                activeLoadAccountID = nil
                isLoading = false
                if refreshAfterActiveLoad && wasCancelled {
                    refreshAfterActiveLoad = false
                    Task { await load(auth: auth, force: true) }
                } else {
                    refreshAfterActiveLoad = false
                }
            }
        }
        do {
            let value = try await TrainingSocialService.shared.load(token: auth.token)
            guard loadedAccountID == accountID, auth.isLoggedIn, auth.accountID == accountID else { return }
            let remoteFeedIDs = Set(value.feed.map(\.id))
            locallyDeletedWorkoutIDs.formIntersection(remoteFeedIDs)
            persistLocallyDeletedWorkoutIDs(accountID: accountID)
            username = value.username; nickname = value.nickname; friends = value.friends; requests = value.requests
            if let remoteBio = value.bio {
                let hasUnpublishedLegacyBio = remoteBio.isEmpty && !bio.isEmpty
                    && !UserDefaults.standard.bool(forKey: detailsSyncedKey(accountID))
                needsBioPublication = hasUnpublishedLegacyBio
                if !hasUnpublishedLegacyBio { bio = remoteBio }
            }
            website = value.website ?? website
            feed = value.feed.filter { !locallyDeletedWorkoutIDs.contains($0.id) }
            errorMessage = nil
            lastNetworkLoadAt = Date()
            saveCache(accountID: accountID)
        } catch {
            guard loadedAccountID == accountID, auth.isLoggedIn, auth.accountID == accountID else { return }
            // Keep cached content visible, but never hide a failed refresh. A
            // populated username/cache previously made feed failures silent,
            // which looked exactly like a friend with no workouts.
            // Pull-to-refresh may cancel the URLSession request as the view
            // task changes. That is expected lifecycle behavior, not a
            // social loading failure.
            if Task.isCancelled || isCancellationError(error) {
                wasCancelled = true
                return
            }
            errorMessage = displayMessage(for: error)
        }
    }

    func updateUsername(_ value: String, auth: AuthManager) async -> Bool {
        do { username = try await auth.updateUsername(value); errorMessage = nil; saveCache(accountID: auth.accountID); return true }
        catch { errorMessage = displayMessage(for: error); return false }
    }

    func updateNickname(_ value: String, auth: AuthManager) async -> Bool {
        do { nickname = try await TrainingSocialService.shared.updateNickname(value, token: auth.token); errorMessage = nil; saveCache(accountID: auth.accountID); return true }
        catch { errorMessage = displayMessage(for: error); return false }
    }

    func updatePublicDetails(bio newBio: String, website newWebsite: String, auth: AuthManager) async -> Bool {
        guard auth.isLoggedIn, !auth.accountID.isEmpty else { return false }
        do {
            let value = try await TrainingSocialService.shared.updatePublicDetails(bio: newBio, website: newWebsite, token: auth.token)
            bio = value.bio
            website = value.website
            UserDefaults.standard.set(bio, forKey: bioKey(auth.accountID))
            UserDefaults.standard.set(true, forKey: detailsSyncedKey(auth.accountID))
            needsBioPublication = false
            errorMessage = nil
            return true
        } catch {
            errorMessage = displayMessage(for: error)
            return false
        }
    }

    func prepareLiveSearch(_ query: String) {
        searchRevision &+= 1
        let canSearch = query.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2
        isSearching = canSearch
        if !canSearch { searchResults = [] }
    }

    func search(_ query: String, auth: AuthManager) async {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        searchRevision &+= 1
        let revision = searchRevision
        guard value.count >= 2, auth.isLoggedIn, !auth.token.isEmpty else {
            searchResults = []
            isSearching = false
            return
        }

        isSearching = true
        do {
            let results = try await TrainingSocialService.shared.search(value, token: auth.token)
            guard !Task.isCancelled, revision == searchRevision else { return }
            searchResults = results
            errorMessage = nil
            isSearching = false
        } catch is CancellationError {
            if revision == searchRevision { isSearching = false }
        } catch {
            guard revision == searchRevision else { return }
            isSearching = false
            errorMessage = displayMessage(for: error)
        }
    }

    func requestFriend(_ user: TrainingSocialUser, auth: AuthManager) async {
        do { try await TrainingSocialService.shared.requestFriend(user.id, token: auth.token); await search(user.username, auth: auth); await load(auth: auth, force: true) }
        catch { errorMessage = displayMessage(for: error) }
    }

    func accept(_ request: TrainingFriendConnection, auth: AuthManager) async -> Bool {
        await action(request.relationshipID, auth: auth, accept: true)
    }
    func remove(_ connection: TrainingFriendConnection, auth: AuthManager) async {
        _ = await action(connection.relationshipID, auth: auth, accept: false)
    }

    func detail(for workoutID: String) -> FriendWorkoutDetail? { workoutDetails[workoutID] }

    func removeFromFeed(workoutID: UUID, remoteFeedID: String?, accountID: String) {
        guard !accountID.isEmpty, loadedAccountID == accountID else { return }
        var feedIDs = Set<String>()
        if let remoteFeedID, !remoteFeedID.isEmpty { feedIDs.insert(remoteFeedID) }
        for item in feed where item.id == workoutID.uuidString || workoutDetails[item.id]?.snapshot?.id == workoutID {
            feedIDs.insert(item.id)
        }
        guard !feedIDs.isEmpty else { return }
        locallyDeletedWorkoutIDs.formUnion(feedIDs)
        persistLocallyDeletedWorkoutIDs(accountID: accountID)
        feed.removeAll { feedIDs.contains($0.id) }
        for id in feedIDs { workoutDetails.removeValue(forKey: id) }
        saveCache(accountID: accountID)
    }

    func loadDetail(id: String, auth: AuthManager, force: Bool = false) async -> FriendWorkout? {
        if !force, let cached = workoutDetails[id]?.workout { return cached }
        do {
            let detail = try await TrainingSocialService.shared.workoutDetail(
                id,
                token: auth.isLoggedIn ? auth.token : nil
            )
            workoutDetails[id] = detail
            workoutDetails[detail.workout.id] = detail
            if !auth.accountID.isEmpty { saveDetail(detail, workoutID: detail.workout.id, accountID: auth.accountID) }
            errorMessage = nil
            return detail.workout
        } catch {
            errorMessage = displayMessage(for: error)
            return nil
        }
    }

    func loadDetail(_ workout: FriendWorkout, auth: AuthManager, force: Bool = false) async {
        if workoutDetails[workout.id] == nil,
           !auth.accountID.isEmpty,
           let cached = restoreDetail(workoutID: workout.id, accountID: auth.accountID) {
            workoutDetails[workout.id] = cached.detail
            if !force, Date().timeIntervalSince(cached.savedAt) < 3_600 { return }
        } else if !force, workoutDetails[workout.id] != nil {
            return
        }
        do {
            workoutDetails[workout.id] = try await TrainingSocialService.shared.workoutDetail(
                workout.id,
                token: auth.isLoggedIn ? auth.token : nil
            )
            if let detail = workoutDetails[workout.id], !auth.accountID.isEmpty {
                saveDetail(detail, workoutID: workout.id, accountID: auth.accountID)
            }
            errorMessage = nil
        } catch { errorMessage = displayMessage(for: error) }
    }

    func toggleLike(_ workoutID: String, auth: AuthManager) async {
        guard let workout = feed.first(where: { $0.id == workoutID }) ?? workoutDetails[workoutID]?.workout else { return }
        let previous = feed.first(where: { $0.id == workoutID })
        if let index = feed.firstIndex(where: { $0.id == workoutID }) {
            feed[index].likedByMe.toggle()
            feed[index].likeCount = max(0, feed[index].likeCount + (feed[index].likedByMe ? 1 : -1))
        }
        do {
            let result = try await TrainingSocialService.shared.toggleLike(workoutID, token: auth.token)
            if let currentIndex = feed.firstIndex(where: { $0.id == workoutID }) {
                feed[currentIndex].likedByMe = result.liked
                feed[currentIndex].likeCount = result.count
            }
            if var detail = workoutDetails[workoutID] {
                detail.workout.likedByMe = result.liked; detail.workout.likeCount = result.count; workoutDetails[workoutID] = detail
                saveDetail(detail, workoutID: workoutID, accountID: auth.accountID)
            }
            errorMessage = nil; saveCache(accountID: auth.accountID)
            await loadDetail(workout, auth: auth, force: true)
        } catch {
            if let previous, let currentIndex = feed.firstIndex(where: { $0.id == workoutID }) {
                feed[currentIndex] = previous
            }
            errorMessage = displayMessage(for: error)
        }
    }

    func addComment(_ body: String, workoutID: String, replyToID: String? = nil, auth: AuthManager) async -> Bool {
        let text = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        do {
            let (comment, count) = try await TrainingSocialService.shared.addComment(text, workoutID: workoutID, replyToID: replyToID, token: auth.token)
            if var detail = workoutDetails[workoutID] {
                detail.comments.append(comment); detail.workout.commentCount = count; workoutDetails[workoutID] = detail
                saveDetail(detail, workoutID: workoutID, accountID: auth.accountID)
            }
            if let index = feed.firstIndex(where: { $0.id == workoutID }) { feed[index].commentCount = count; saveCache(accountID: auth.accountID) }
            errorMessage = nil; return true
        } catch { errorMessage = displayMessage(for: error); return false }
    }

    private func action(_ id: String, auth: AuthManager, accept: Bool) async -> Bool {
        do {
            if accept { try await TrainingSocialService.shared.accept(id, token: auth.token) }
            else { try await TrainingSocialService.shared.remove(id, token: auth.token) }
            await load(auth: auth, force: true)
            return true
        } catch {
            errorMessage = displayMessage(for: error)
            return false
        }
    }

    private func cacheKey(_ accountID: String) -> String { "training_social_\(accountID)_v1" }
    private func bioKey(_ accountID: String) -> String { "training_social_bio_\(accountID)_v1" }
    private func detailsSyncedKey(_ accountID: String) -> String { "training_social_details_synced_\(accountID)_v1" }
    private func locallyDeletedWorkoutKey(_ accountID: String) -> String { "training_social_deleted_workouts_\(accountID)_v1" }

    private func restoreCache(accountID: String) {
        guard let data = UserDefaults.standard.data(forKey: cacheKey(accountID)),
              let cached = try? JSONDecoder().decode(CachedState.self, from: data) else { return }
        username = cached.username
        nickname = cached.nickname ?? ""
        friends = cached.friends
        requests = cached.requests
        locallyDeletedWorkoutIDs = Set(UserDefaults.standard.stringArray(forKey: locallyDeletedWorkoutKey(accountID)) ?? [])
        feed = cached.feed.filter { !locallyDeletedWorkoutIDs.contains($0.id) }
        lastNetworkLoadAt = cached.savedAt
    }

    private func persistLocallyDeletedWorkoutIDs(accountID: String) {
        UserDefaults.standard.set(Array(locallyDeletedWorkoutIDs), forKey: locallyDeletedWorkoutKey(accountID))
    }

    private func saveCache(accountID: String) {
        guard !accountID.isEmpty else { return }
        let value = CachedState(username: username, nickname: nickname, friends: friends, requests: requests, feed: feed, savedAt: Date())
        UserDefaults.standard.set(try? JSONEncoder().encode(value), forKey: cacheKey(accountID))
    }

    private func displayMessage(for error: Error) -> String {
        if let authError = error as? AuthError, case .network = authError {
            return LanguageStore.localizedString("training.social.network_error")
        }
        if isNetworkError(error) {
            return LanguageStore.localizedString("training.social.network_error")
        }
        return error.localizedDescription == "training.social.error"
            ? LanguageStore.localizedString("training.social.error")
            : error.localizedDescription
    }

    private func isCancellationError(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled { return true }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
            return isCancellationError(underlying)
        }
        return false
    }

    private func isNetworkError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain { return true }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
            return isNetworkError(underlying)
        }
        return false
    }

    private struct CachedDetail: Codable {
        let detail: FriendWorkoutDetail
        let savedAt: Date
    }

    private func detailURL(workoutID: String, accountID: String) -> URL? {
        guard !accountID.isEmpty, !workoutID.isEmpty else { return nil }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Hyse/TrainingSocial/\(accountID)", isDirectory: true)
            .appendingPathComponent("\(workoutID).json")
    }

    private func restoreDetail(workoutID: String, accountID: String) -> CachedDetail? {
        guard let url = detailURL(workoutID: workoutID, accountID: accountID),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(CachedDetail.self, from: data)
    }

    private func saveDetail(_ detail: FriendWorkoutDetail, workoutID: String, accountID: String) {
        guard let url = detailURL(workoutID: workoutID, accountID: accountID),
              let data = try? JSONEncoder().encode(CachedDetail(detail: detail, savedAt: Date())) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}

nonisolated enum GymCommunityChannel: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case news, members
    var id: String { rawValue }
    var localizationKey: String { "training.community.channel.\(rawValue)" }
}

nonisolated enum GymCommunityPostDeliveryState: String, Codable, Hashable, Sendable {
    case sending
    case sent
    case failed
}

private struct CommunityRequestError: LocalizedError {
    let status: Int
    let message: String
    var errorDescription: String? { message }
}

nonisolated struct GymCommunity: Codable, Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    var gymName: String
    var city: String
    var description: String
    var image: String? = nil
    var imageURL: String? = nil
    // Keeps the just-uploaded image visible immediately while the server
    // response/cache settles. It is intentionally not persisted in Codable
    // community caches because the server remains the durable image source.
    var localImageData: Data? = nil
    var ownerID: String
    var ownerUsername: String
    var memberCount: Int
    var joined: Bool
    var role: String
    var newsNotificationsEnabled: Bool?
    enum CodingKeys: String, CodingKey {
        case id, name, city, description, image, joined, role
        case gymName = "gym_name", ownerID = "owner_id", ownerUsername = "owner_username", memberCount = "member_count"
        case imageURL = "image_url"
        case newsNotificationsEnabled = "news_notifications_enabled"
    }
    var receivesNewsNotifications: Bool { newsNotificationsEnabled ?? false }
}

nonisolated struct GymCommunityPost: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let communityID: String
    let authorID: String
    let authorUsername: String
    let authorNickname: String?
    let avatar: String?
    let avatarURL: String?
    let channel: GymCommunityChannel
    var body: String
    var images: [String]? = nil
    var imageURLs: [String]? = nil
    let pinned: Bool
    let reply: GymCommunityReplyPreview?
    var reactions: [GymCommunityReaction]?
    let created: String
    var updated: String?
    var clientID: String?
    var deliveryState: GymCommunityPostDeliveryState?
    enum CodingKeys: String, CodingKey {
        case id, avatar, channel, body, images, pinned, reply, reactions, created, updated
        case imageURLs = "image_urls"
        case communityID = "community_id", authorID = "author_id", authorUsername = "author_username", authorNickname = "author_nickname", avatarURL = "avatar_url"
        case clientID = "client_id", deliveryState = "delivery_state"
    }
    var date: Date? { Self.fractionalFormatter.date(from: created) ?? ISO8601DateFormatter().date(from: created) }
    var wasEdited: Bool { updated.map { !$0.isEmpty && $0 != created } ?? false }
    var isWaitingForServer: Bool { deliveryState == .sending }
    var authorDisplayName: String { let value = authorNickname?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""; return value.isEmpty ? authorUsername : value }
    private static let fractionalFormatter: ISO8601DateFormatter = {
        let value = ISO8601DateFormatter(); value.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return value
    }()
}

nonisolated struct GymCommunityReplyPreview: Codable, Hashable, Sendable {
    let id: String
    var authorID: String? = nil
    let authorUsername: String
    let authorNickname: String?
    let body: String
    enum CodingKeys: String, CodingKey {
        case id, body
        case authorID = "author_id"
        case authorUsername = "author_username", authorNickname = "author_nickname"
    }
    var authorDisplayName: String { let value = authorNickname?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""; return value.isEmpty ? authorUsername : value }
}

nonisolated struct GymCommunityReaction: Codable, Identifiable, Hashable, Sendable {
    let emoji: String
    let count: Int
    let reacted: Bool
    var id: String { emoji }
}

nonisolated struct GymCommunityMember: Codable, Identifiable, Hashable, Sendable {
    let userID: String
    let username: String
    let nickname: String?
    let avatar: String?
    let avatarURL: String?
    var role: String
    let joinedAt: String
    var id: String { userID }
    enum CodingKeys: String, CodingKey {
        case username, nickname, avatar, role
        case userID = "user_id", avatarURL = "avatar_url", joinedAt = "joined_at"
    }
    var displayName: String { let value = nickname?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""; return value.isEmpty ? username : value }
}

nonisolated struct GymCommunityDetail: Codable, Hashable, Sendable {
    var community: GymCommunity
    var posts: [GymCommunityPost]
    var members: [GymCommunityMember]? = nil
    var supportsMessageOutbox: Bool? = nil
    var memberList: [GymCommunityMember] { members ?? [] }
}

nonisolated enum ContentReportTargetType: String, Codable, CaseIterable, Identifiable, Sendable {
    case user, avatar, community, communityPost = "community_post", workout, workoutComment = "workout_comment"
    var id: String { rawValue }
}

nonisolated struct ContentReportTarget: Identifiable, Hashable, Sendable {
    let type: ContentReportTargetType
    let id: String
    let displayName: String
    var targetID: String { id }
    var reportID: String { "\(type.rawValue):\(id)" }

    static func profile(id: String, name: String) -> Self { .init(type: .user, id: id, displayName: name) }
    static func avatar(id: String, name: String) -> Self { .init(type: .avatar, id: id, displayName: name) }
    static func community(id: String, name: String) -> Self { .init(type: .community, id: id, displayName: name) }
    static func message(id: String, name: String) -> Self { .init(type: .communityPost, id: id, displayName: name) }
    static func workout(id: String, name: String) -> Self { .init(type: .workout, id: id, displayName: name) }
    static func workoutComment(id: String, name: String) -> Self { .init(type: .workoutComment, id: id, displayName: name) }
}

nonisolated enum ContentReportReason: String, Codable, CaseIterable, Identifiable, Sendable {
    case illegal, harassment, hate, sexual, violence, privacy, spam, intellectualProperty = "intellectual_property", other
    var id: String { rawValue }
    var localizationKey: String { "content_reports.reason.\(rawValue)" }
}

nonisolated struct ContentReport: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let targetType: ContentReportTargetType
    let targetID: String
    let targetLabel: String
    let reason: ContentReportReason
    let status: String
    let decisionCode: String
    let decisionReason: String
    let appealDetails: String
    let created: String
    let updated: String
    enum CodingKeys: String, CodingKey {
        case id, targetLabel = "target_label", targetID = "target_id", targetType = "target_type", reason, status
        case decisionCode = "decision_code", decisionReason = "decision_reason", appealDetails = "appeal_details", created, updated
    }
}

actor ContentReportService {
    static let shared = ContentReportService()
    private let baseURL = HyseConfiguration.serverURL
    private struct ReportResponse: Decodable { let report: ContentReport }
    private struct ReportsResponse: Decodable { let reports: [ContentReport] }
    private struct PublicReportResponse: Decodable { let id: String }

    func submit(target: ContentReportTarget, reason: ContentReportReason, details: String, token: String) async throws -> ContentReport {
        let response: ReportResponse = try await request(
            path: "/api/hyse/reports", method: "POST", token: token,
            body: ["target_type": target.type.rawValue, "target_id": target.targetID, "reason": reason.rawValue, "details": details, "good_faith": "true"]
        )
        return response.report
    }

    func submitPublic(location: String, contactEmail: String, reason: ContentReportReason, details: String) async throws -> String {
        let response: PublicReportResponse = try await request(
            path: "/api/hyse/reports/public", method: "POST", token: "",
            body: ["target_location": location, "contact_email": contactEmail, "reason": reason.rawValue,
                   "details": details, "good_faith": "true"]
        )
        return response.id
    }

    func list(token: String) async throws -> [ContentReport] {
        let response: ReportsResponse = try await request(path: "/api/hyse/reports", method: "GET", token: token, body: nil)
        return response.reports
    }

    func appeal(reportID: String, details: String, token: String) async throws -> ContentReport {
        let response: ReportResponse = try await request(path: "/api/hyse/reports/\(reportID)/appeal", method: "POST", token: token, body: ["details": details])
        return response.report
    }

    private func request<T: Decodable>(path: String, method: String, token: String, body: [String: String]?) async throws -> T {
        guard let url = URL(string: baseURL + path) else { throw TrainingSocialError.invalidURL }
        var request = URLRequest(url: url); request.httpMethod = method; request.timeoutInterval = 25
        if !token.isEmpty { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body { request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.httpBody = try JSONEncoder().encode(body) }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["message"] as? String
            throw TrainingSocialError.server(message ?? "content_reports.error")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

actor GymCommunityService {
    static let shared = GymCommunityService()
    private let baseURL = HyseConfiguration.serverURL
    private struct ListResponse: Decodable { let items: [GymCommunity] }
    private struct JoinResponse: Decodable { let joined: Bool; let role: String? }
    private struct PostResponse: Decodable { let post: GymCommunityPost }
    private struct DeleteResponse: Decodable { let deleted: Bool; let id: String }
    private struct ReactionResponse: Decodable { let reactions: [GymCommunityReaction] }
    private struct NotificationResponse: Decodable { let enabled: Bool }
    private struct MemberResponse: Decodable { let member: GymCommunityMember }

    func communities(query: String, token: String) async throws -> [GymCommunity] {
        var components = URLComponents(string: "\(baseURL)/api/hyse/gym-communities")!
        if !query.isEmpty { components.queryItems = [URLQueryItem(name: "q", value: query)] }
        let response: ListResponse = try await send(url: components.url!, method: "GET", token: token, body: nil)
        return response.items
    }

    func detail(id: String, token: String) async throws -> GymCommunityDetail {
        try await request(path: "/api/hyse/gym-communities/\(id)", method: "GET", token: token, body: nil)
    }

    func create(name: String, gymName: String, city: String, description: String, imageData: Data?, token: String) async throws -> GymCommunity {
        guard let url = URL(string: baseURL + "/api/hyse/gym-communities") else { throw TrainingSocialError.invalidURL }
        let boundary = "HyseCommunity-\(UUID().uuidString)"
        var body = Data()
        for (field, value) in ["name": name, "gym_name": gymName, "city": city, "description": description] {
            body.append(Data("--\(boundary)\r\n".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"\(field)\"\r\n\r\n".utf8))
            body.append(Data(value.utf8))
            body.append(Data("\r\n".utf8))
        }
        if let imageData {
            body.append(Data("--\(boundary)\r\n".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"image\"; filename=\"community.jpg\"\r\n".utf8))
            body.append(Data("Content-Type: image/jpeg\r\n\r\n".utf8))
            body.append(imageData)
            body.append(Data("\r\n".utf8))
        }
        body.append(Data("--\(boundary)--\r\n".utf8))

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(statusCode) else {
            let serverMessage = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["message"] as? String
            let message = statusCode >= 500 || serverMessage == "Something went wrong while processing your request."
                ? "training.community.error"
                : (serverMessage ?? "training.community.error")
            throw TrainingSocialError.server(message)
        }
        return try JSONDecoder().decode(GymCommunity.self, from: data)
    }

    func join(id: String, token: String) async throws -> String {
        let response: JoinResponse = try await request(path: "/api/hyse/gym-communities/\(id)/join", method: "POST", token: token, body: [:])
        return response.role ?? "member"
    }

    func leave(id: String, token: String) async throws {
        let _: JoinResponse = try await request(path: "/api/hyse/gym-communities/\(id)/leave", method: "POST", token: token, body: [:])
    }

    func deleteCommunity(id: String, token: String) async throws {
        let response: DeleteResponse = try await request(path: "/api/hyse/gym-communities/\(id)", method: "DELETE", token: token, body: nil)
        guard response.deleted, response.id == id else { throw TrainingSocialError.server("training.community.error") }
    }

    func post(body: String, channel: GymCommunityChannel, communityID: String, replyToID: String?, clientID: String, token: String) async throws -> GymCommunityPost {
        var payload = ["body": body, "channel": channel.rawValue]
        if let replyToID { payload["reply_to"] = replyToID }
        payload["client_id"] = clientID
        let response: PostResponse = try await request(path: "/api/hyse/gym-communities/\(communityID)/posts", method: "POST", token: token, body: payload)
        return response.post
    }

    func postNewsWithImages(body: String, images: [Data], communityID: String, replyToID: String?, clientID: String, token: String) async throws -> GymCommunityPost {
        guard !images.isEmpty, images.count <= 4,
              let url = URL(string: baseURL + "/api/hyse/gym-communities/\(communityID)/posts")
        else { throw TrainingSocialError.invalidURL }
        let boundary = "HyseNews-\(UUID().uuidString)"
        var multipart = Data()
        var fields = ["body": body, "channel": "news", "client_id": clientID]
        if let replyToID { fields["reply_to"] = replyToID }
        for (name, value) in fields {
            multipart.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
        }
        for (index, image) in images.enumerated() {
            multipart.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"images\"; filename=\"news-\(index + 1).jpg\"\r\nContent-Type: image/jpeg\r\n\r\n".utf8))
            multipart.append(image)
            multipart.append(Data("\r\n".utf8))
        }
        multipart.append(Data("--\(boundary)--\r\n".utf8))
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = multipart
        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(statusCode) else {
            let serverMessage = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["message"] as? String
            let message = statusCode >= 500 || serverMessage == "Something went wrong while processing your request."
                ? "training.community.error" : (serverMessage ?? "training.community.error")
            throw CommunityRequestError(status: statusCode, message: message)
        }
        return try JSONDecoder().decode(PostResponse.self, from: data).post
    }

    func editPost(id: String, body: String, token: String) async throws -> GymCommunityPost {
        let response: PostResponse = try await request(path: "/api/hyse/gym-community-posts/\(id)", method: "PATCH", token: token, body: ["body": body])
        return response.post
    }

    func editNewsPostImages(id: String, body: String, keepImages: [String], newImages: [Data], token: String) async throws -> GymCommunityPost {
        guard keepImages.count + newImages.count <= 4,
              let url = URL(string: baseURL + "/api/hyse/gym-community-posts/\(id)"),
              let keepData = try? JSONEncoder().encode(keepImages),
              let keepJSON = String(data: keepData, encoding: .utf8)
        else { throw TrainingSocialError.invalidURL }
        let boundary = "HyseNewsEdit-\(UUID().uuidString)"
        var multipart = Data()
        for (name, value) in ["body": body, "keep_images": keepJSON] {
            multipart.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
        }
        for (index, image) in newImages.enumerated() {
            multipart.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"images\"; filename=\"news-\(index + 1).jpg\"\r\nContent-Type: image/jpeg\r\n\r\n".utf8))
            multipart.append(image)
            multipart.append(Data("\r\n".utf8))
        }
        multipart.append(Data("--\(boundary)--\r\n".utf8))
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.timeoutInterval = 45
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = multipart
        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(statusCode) else {
            let serverMessage = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["message"] as? String
            let message = statusCode >= 500 || serverMessage == "Something went wrong while processing your request."
                ? "training.community.error" : (serverMessage ?? "training.community.error")
            throw CommunityRequestError(status: statusCode, message: message)
        }
        return try JSONDecoder().decode(PostResponse.self, from: data).post
    }

    func deletePost(id: String, token: String) async throws {
        let response: DeleteResponse = try await request(path: "/api/hyse/gym-community-posts/\(id)", method: "DELETE", token: token, body: nil)
        guard response.deleted, response.id == id else { throw TrainingSocialError.server("training.community.error") }
    }

    func toggleReaction(postID: String, emoji: String, token: String) async throws -> [GymCommunityReaction] {
        let response: ReactionResponse = try await request(path: "/api/hyse/gym-community-posts/\(postID)/reactions", method: "POST", token: token, body: ["emoji": emoji])
        return response.reactions
    }

    func setNewsNotifications(communityID: String, enabled: Bool, token: String) async throws -> Bool {
        let response: NotificationResponse = try await request(
            path: "/api/hyse/gym-communities/\(communityID)/news-notifications",
            method: "POST",
            token: token,
            body: ["enabled": enabled ? "true" : "false"]
        )
        return response.enabled
    }

    func setMemberRole(communityID: String, userID: String, role: String, token: String) async throws -> GymCommunityMember {
        let response: MemberResponse = try await request(
            path: "/api/hyse/gym-communities/\(communityID)/members/\(userID)/role",
            method: "PATCH",
            token: token,
            body: ["role": role]
        )
        return response.member
    }

    private func request<T: Decodable>(path: String, method: String, token: String, body: [String: String]?) async throws -> T {
        guard let url = URL(string: baseURL + path) else { throw TrainingSocialError.invalidURL }
        return try await send(url: url, method: method, token: token, body: body)
    }

    private func send<T: Decodable>(url: URL, method: String, token: String, body: [String: String]?) async throws -> T {
        var request = URLRequest(url: url); request.httpMethod = method
        request.timeoutInterval = 25
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body { request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.httpBody = try JSONEncoder().encode(body) }
        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(statusCode) else {
            let serverMessage = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["message"] as? String
            // PocketBase intentionally hides internal details behind this
            // English fallback. Do not leak it into an otherwise localized UI.
            let message = statusCode >= 500 || serverMessage == "Something went wrong while processing your request."
                ? "training.community.error"
                : (serverMessage ?? "training.community.error")
            throw CommunityRequestError(status: statusCode, message: message)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

@MainActor
final class GymCommunityStore: ObservableObject {
    @Published private(set) var communities: [GymCommunity] = []
    @Published private(set) var details: [String: GymCommunityDetail] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var isPosting = false
    @Published private(set) var postActionsInFlight: Set<String> = []
    @Published private(set) var errorMessage: String?
    private var loadedAccountID: String?
    private var lastLoadedAt: Date?
    private var searchRevision: UInt = 0
    private var messageSyncTask: Task<Void, Never>?
    private var messageRetryTask: Task<Void, Never>?
    private var messageRetryAttempt = 0
    private var outboxCapableCommunities: Set<String> = []
    private let freshness: TimeInterval = 900

    private struct Cache: Codable { let communities: [GymCommunity]; let details: [String: GymCommunityDetail]; let savedAt: Date }

    func activate(auth: AuthManager) {
        let accountID = auth.isLoggedIn ? auth.accountID : nil
        if loadedAccountID != accountID {
            messageSyncTask?.cancel(); messageSyncTask = nil
            messageRetryTask?.cancel(); messageRetryTask = nil
            messageRetryAttempt = 0
            outboxCapableCommunities = []
            searchRevision &+= 1
            loadedAccountID = accountID
            communities = []; details = [:]; lastLoadedAt = nil
            if let accountID { restore(accountID: accountID) }
        }
        syncPendingMessages(auth: auth)
    }

    func load(auth: AuthManager, query: String = "", force: Bool = false) async {
        activate(auth: auth)
        guard auth.isLoggedIn, !auth.token.isEmpty else { return }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty, !force, let lastLoadedAt, Date().timeIntervalSince(lastLoadedAt) < freshness { return }
        searchRevision &+= 1; let revision = searchRevision
        // A manual refresh starts a new request. Do not keep a banner from a
        // prior request visible while this request is in flight, especially
        // when SwiftUI cancels the previous refresh task.
        if force { errorMessage = nil }
        isLoading = communities.isEmpty
        defer { if revision == searchRevision { isLoading = false } }
        do {
            let values = try await GymCommunityService.shared.communities(query: trimmed, token: auth.token)
            guard !Task.isCancelled, revision == searchRevision else { return }
            communities = values.map { preservingLocalImageData(in: $0) }; errorMessage = nil
            if trimmed.isEmpty { lastLoadedAt = Date(); save(accountID: auth.accountID) }
        } catch {
            // Pull-to-refresh can cancel the previous URLSession task while a
            // new request is starting. That is expected UI lifecycle behavior,
            // not a community loading failure, so do not show an error banner.
            guard !Task.isCancelled, !isCancellationError(error), revision == searchRevision else { return }
            errorMessage = displayMessage(error)
        }
    }

    func loadDetail(id: String, auth: AuthManager, force: Bool = false) async {
        guard auth.isLoggedIn, loadedAccountID == auth.accountID else { return }
        let accountID = auth.accountID
        syncPendingMessages(auth: auth)
        if !force, details[id] != nil { return }
        let alreadyConfirmedIDs = Set((details[id]?.posts ?? []).filter {
            $0.deliveryState == nil || $0.deliveryState == .sent
        }.map(\.id))
        do {
            var value = try await GymCommunityService.shared.detail(id: id, token: auth.token)
            guard loadedAccountID == accountID, auth.accountID == accountID else { return }
            let localPending = details[id]?.posts.filter {
                $0.clientID != nil && ($0.isWaitingForServer || $0.deliveryState == .failed || !alreadyConfirmedIDs.contains($0.id))
            } ?? []
            let deliveredClientIDs = Set(value.posts.compactMap(\.clientID))
            value.posts.append(contentsOf: localPending.filter { post in
                guard let clientID = post.clientID else { return true }
                return !deliveredClientIDs.contains(clientID)
            })
            value.community = preservingLocalImageData(in: value.community)
            details[id] = value; merge(value.community); errorMessage = nil; save(accountID: auth.accountID)
            syncPendingMessages(auth: auth)
        } catch {
            guard !Task.isCancelled, !isCancellationError(error) else { return }
            errorMessage = displayMessage(error)
        }
    }

    func create(name: String, gymName: String, city: String, description: String, imageData: Data?, auth: AuthManager) async -> GymCommunity? {
        do {
            var value = try await GymCommunityService.shared.create(name: name, gymName: gymName, city: city, description: description, imageData: imageData, token: auth.token)
            value.localImageData = imageData
            merge(value); errorMessage = nil; save(accountID: auth.accountID); return value
        } catch { errorMessage = displayMessage(error); return nil }
    }

    func join(_ community: GymCommunity, auth: AuthManager) async -> Bool {
        do {
            let role = try await GymCommunityService.shared.join(id: community.id, token: auth.token)
            var value = community; value.joined = true; value.role = role; value.memberCount += 1; merge(value)
            await loadDetail(id: community.id, auth: auth, force: true)
            save(accountID: auth.accountID)
            return true
        } catch {
            errorMessage = displayMessage(error)
            return false
        }
    }

    func leave(_ community: GymCommunity, auth: AuthManager) async -> Bool {
        do {
            try await GymCommunityService.shared.leave(id: community.id, token: auth.token)
            var value = community; value.joined = false; value.role = ""; value.memberCount = max(0, value.memberCount - 1); merge(value)
            details[community.id] = GymCommunityDetail(community: value, posts: []); errorMessage = nil; save(accountID: auth.accountID); return true
        } catch { errorMessage = displayMessage(error); return false }
    }

    func deleteCommunity(_ community: GymCommunity, auth: AuthManager) async -> Bool {
        guard !postActionsInFlight.contains(community.id) else { return false }
        postActionsInFlight.insert(community.id); defer { postActionsInFlight.remove(community.id) }
        do {
            try await GymCommunityService.shared.deleteCommunity(id: community.id, token: auth.token)
            communities.removeAll { $0.id == community.id }
            details.removeValue(forKey: community.id)
            errorMessage = nil; save(accountID: auth.accountID); return true
        } catch { errorMessage = displayMessage(error); return false }
    }

    func send(_ text: String, channel: GymCommunityChannel, communityID: String, replyTo: GymCommunityPost? = nil, auth: AuthManager) -> Bool {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, body.utf16.count <= 2000, auth.isLoggedIn,
              loadedAccountID == auth.accountID else { return false }
        let clientID = UUID().uuidString.lowercased()
        let replyPreview = replyTo.map {
            GymCommunityReplyPreview(id: $0.id, authorID: $0.authorID, authorUsername: $0.authorUsername, authorNickname: $0.authorNickname, body: String($0.body.prefix(500)))
        }
        let pendingPost = GymCommunityPost(
            id: "pending:\(clientID)",
            communityID: communityID,
            authorID: auth.accountID,
            authorUsername: auth.accountName,
            authorNickname: nil,
            avatar: auth.accountAvatarFilename.isEmpty ? nil : auth.accountAvatarFilename,
            avatarURL: auth.accountAvatarURL?.absoluteString,
            channel: channel,
            body: body,
            pinned: false,
            reply: replyPreview,
            reactions: [],
            created: ISO8601DateFormatter().string(from: Date()),
            updated: nil,
            clientID: clientID,
            deliveryState: .sending
        )
        if var detail = details[communityID] {
            detail.posts.append(pendingPost)
            details[communityID] = detail
        } else {
            return false
        }
        errorMessage = nil
        save(accountID: auth.accountID)
        syncPendingMessages(auth: auth)
        return true
    }

    func publishNewsWithImages(_ text: String, images: [Data], communityID: String, replyTo: GymCommunityPost?, clientID: String, auth: AuthManager) async -> Bool {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, body.utf16.count <= 2000,
              !images.isEmpty, images.count <= 4,
              auth.isLoggedIn, loadedAccountID == auth.accountID,
              let role = details[communityID]?.community.role,
              role == "owner" || role == "admin" else { return false }
        let accountID = auth.accountID
        do {
            let post = try await GymCommunityService.shared.postNewsWithImages(
                body: body, images: images, communityID: communityID,
                replyToID: replyTo?.id, clientID: clientID, token: auth.token
            )
            guard loadedAccountID == accountID, auth.accountID == accountID else { return false }
            if var detail = details[communityID] {
                if !detail.posts.contains(where: { $0.id == post.id }) { detail.posts.append(post) }
                details[communityID] = detail
            }
            errorMessage = nil
            save(accountID: accountID)
            return true
        } catch {
            guard loadedAccountID == accountID else { return false }
            errorMessage = displayMessage(error)
            return false
        }
    }

    func syncPendingMessages(auth: AuthManager) {
        guard messageSyncTask == nil, auth.isLoggedIn, !auth.token.isEmpty,
              loadedAccountID == auth.accountID,
              let pending = nextPendingMessage() else {
            isPosting = messageSyncTask != nil
            return
        }
        messageRetryTask?.cancel(); messageRetryTask = nil
        isPosting = true
        let accountID = auth.accountID
        let token = auth.token
        messageSyncTask = Task { [weak self] in
            guard let self, let clientID = pending.clientID else { return }
            do {
                // Older servers ignore client IDs. Never retry writes against
                // them until they explicitly advertise duplicate protection.
                if !self.outboxCapableCommunities.contains(pending.communityID) {
                    let remote = try await GymCommunityService.shared.detail(id: pending.communityID, token: token)
                    guard remote.supportsMessageOutbox == true else {
                        throw URLError(.resourceUnavailable)
                    }
                    self.outboxCapableCommunities.insert(pending.communityID)
                }
                guard !Task.isCancelled, self.loadedAccountID == accountID,
                      auth.isLoggedIn, auth.accountID == accountID else { return }
                var delivered = try await GymCommunityService.shared.post(
                    body: pending.body,
                    channel: pending.channel,
                    communityID: pending.communityID,
                    replyToID: pending.reply?.id,
                    clientID: clientID,
                    token: token
                )
                guard !Task.isCancelled, self.loadedAccountID == accountID,
                      auth.isLoggedIn, auth.accountID == accountID else { return }
                delivered.deliveryState = .sent
                delivered.clientID = delivered.clientID ?? clientID
                self.replacePendingMessage(clientID: clientID, with: delivered)
                self.errorMessage = nil
                self.messageRetryAttempt = 0
                self.save(accountID: accountID)
                self.messageSyncTask = nil
                self.isPosting = false
                self.syncPendingMessages(auth: auth)
            } catch is CancellationError {
                guard self.loadedAccountID == accountID else { return }
                self.messageSyncTask = nil
                self.isPosting = false
            } catch {
                guard !Task.isCancelled, self.loadedAccountID == accountID else { return }
                self.messageSyncTask = nil
                self.isPosting = false
                if let failure = error as? CommunityRequestError,
                   (400...499).contains(failure.status),
                   ![401, 408, 429].contains(failure.status) {
                    var failed = pending
                    failed.deliveryState = .failed
                    self.replacePendingMessage(clientID: clientID, with: failed)
                    self.save(accountID: accountID)
                    self.syncPendingMessages(auth: auth)
                    return
                }
                self.scheduleMessageRetry(accountID: accountID, auth: auth)
            }
        }
    }

    func edit(_ post: GymCommunityPost, text: String, keepImages: [String], newImages: [Data], auth: AuthManager) async -> Bool {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, !postActionsInFlight.contains(post.id) else { return false }
        postActionsInFlight.insert(post.id); defer { postActionsInFlight.remove(post.id) }
        do {
            let imageChanged = post.channel == .news &&
                (keepImages != (post.images ?? []) || !newImages.isEmpty)
            let updated: GymCommunityPost
            if imageChanged {
                updated = try await GymCommunityService.shared.editNewsPostImages(
                    id: post.id, body: body, keepImages: keepImages,
                    newImages: newImages, token: auth.token
                )
            } else {
                updated = try await GymCommunityService.shared.editPost(id: post.id, body: body, token: auth.token)
            }
            replacePost(updated); errorMessage = nil; save(accountID: auth.accountID); return true
        } catch { errorMessage = displayMessage(error); return false }
    }

    func delete(_ post: GymCommunityPost, auth: AuthManager) async -> Bool {
        guard !postActionsInFlight.contains(post.id) else { return false }
        postActionsInFlight.insert(post.id); defer { postActionsInFlight.remove(post.id) }
        do {
            try await GymCommunityService.shared.deletePost(id: post.id, token: auth.token)
            if var detail = details[post.communityID] {
                detail.posts.removeAll { $0.id == post.id }; details[post.communityID] = detail
            }
            errorMessage = nil; save(accountID: auth.accountID); return true
        } catch { errorMessage = displayMessage(error); return false }
    }

    func toggleReaction(_ emoji: String, on post: GymCommunityPost, auth: AuthManager) async {
        let actionID = "\(post.id):\(emoji)"
        guard !postActionsInFlight.contains(actionID) else { return }
        postActionsInFlight.insert(actionID); defer { postActionsInFlight.remove(actionID) }
        do {
            let reactions = try await GymCommunityService.shared.toggleReaction(postID: post.id, emoji: emoji, token: auth.token)
            guard var detail = details[post.communityID], let index = detail.posts.firstIndex(where: { $0.id == post.id }) else { return }
            detail.posts[index].reactions = reactions; details[post.communityID] = detail
            errorMessage = nil; save(accountID: auth.accountID)
        } catch { errorMessage = displayMessage(error) }
    }

    func setNewsNotifications(_ enabled: Bool, for community: GymCommunity, auth: AuthManager) async -> Bool {
        let actionID = "\(community.id):notifications"
        guard !postActionsInFlight.contains(actionID) else { return false }
        postActionsInFlight.insert(actionID); defer { postActionsInFlight.remove(actionID) }
        do {
            let saved = try await GymCommunityService.shared.setNewsNotifications(communityID: community.id, enabled: enabled, token: auth.token)
            var updated = community
            updated.newsNotificationsEnabled = saved
            merge(updated)
            if var detail = details[community.id] {
                detail.community = updated
                details[community.id] = detail
            }
            errorMessage = nil; save(accountID: auth.accountID)
            return true
        } catch {
            errorMessage = displayMessage(error)
            return false
        }
    }

    func setMemberRole(_ role: String, member: GymCommunityMember, communityID: String, auth: AuthManager) async -> Bool {
        let actionID = "\(communityID):role:\(member.userID)"
        guard !postActionsInFlight.contains(actionID) else { return false }
        postActionsInFlight.insert(actionID); defer { postActionsInFlight.remove(actionID) }
        do {
            let updated = try await GymCommunityService.shared.setMemberRole(
                communityID: communityID,
                userID: member.userID,
                role: role,
                token: auth.token
            )
            if var detail = details[communityID], var members = detail.members,
               let index = members.firstIndex(where: { $0.userID == updated.userID }) {
                members[index] = updated
                detail.members = members.sorted { memberRoleRank($0.role) < memberRoleRank($1.role) || (memberRoleRank($0.role) == memberRoleRank($1.role) && $0.username < $1.username) }
                details[communityID] = detail
            }
            errorMessage = nil; save(accountID: auth.accountID)
            return true
        } catch {
            errorMessage = displayMessage(error)
            return false
        }
    }

    func detail(_ id: String) -> GymCommunityDetail? { details[id] }
    func community(_ id: String) -> GymCommunity? {
        details[id]?.community ?? communities.first(where: { $0.id == id })
    }
    func clearError() { errorMessage = nil }

    func retryMessage(_ post: GymCommunityPost, auth: AuthManager) {
        guard post.authorID == auth.accountID, post.deliveryState == .failed,
              let clientID = post.clientID else { return }
        var pending = post
        pending.deliveryState = .sending
        replacePendingMessage(clientID: clientID, with: pending)
        save(accountID: auth.accountID)
        syncPendingMessages(auth: auth)
    }

    private func nextPendingMessage() -> GymCommunityPost? {
        details.values
            .flatMap(\.posts)
            .filter(\.isWaitingForServer)
            .sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
            .first
    }

    private func replacePendingMessage(clientID: String, with delivered: GymCommunityPost) {
        guard var detail = details[delivered.communityID],
              let index = detail.posts.firstIndex(where: { $0.clientID == clientID }) else { return }
        if detail.posts[index].deliveryState == nil || detail.posts[index].deliveryState == .sent { return }
        detail.posts[index] = delivered
        details[delivered.communityID] = detail
    }

    private func scheduleMessageRetry(accountID: String, auth: AuthManager) {
        guard messageRetryTask == nil, loadedAccountID == accountID else { return }
        let delays: [Duration] = [.seconds(2), .seconds(5), .seconds(15), .seconds(30), .seconds(60)]
        let delay = delays[min(messageRetryAttempt, delays.count - 1)]
        messageRetryAttempt = min(messageRetryAttempt + 1, delays.count - 1)
        messageRetryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, self.loadedAccountID == accountID else { return }
            self.messageRetryTask = nil
            self.syncPendingMessages(auth: auth)
        }
    }

    private func merge(_ value: GymCommunity) {
        let mergedValue = preservingLocalImageData(in: value)
        if let index = communities.firstIndex(where: { $0.id == mergedValue.id }) { communities[index] = mergedValue }
        else { communities.insert(mergedValue, at: 0) }
        communities.sort { ($0.joined ? 0 : 1, -$0.memberCount, $0.name) < ($1.joined ? 0 : 1, -$1.memberCount, $1.name) }
    }

    private func preservingLocalImageData(in value: GymCommunity) -> GymCommunity {
        guard value.localImageData == nil else { return value }
        var value = value
        value.localImageData = communities.first(where: { $0.id == value.id })?.localImageData
            ?? details[value.id]?.community.localImageData
        return value
    }
    private func replacePost(_ post: GymCommunityPost) {
        guard var detail = details[post.communityID], let index = detail.posts.firstIndex(where: { $0.id == post.id }) else { return }
        detail.posts[index] = post; details[post.communityID] = detail
    }
    private func memberRoleRank(_ role: String) -> Int {
        role == "owner" ? 0 : (role == "admin" ? 1 : 2)
    }
    private func cacheKey(_ accountID: String) -> String { "gym_communities_\(accountID)_v1" }
    private func restore(accountID: String) {
        communities = []; details = [:]; lastLoadedAt = nil
        guard let data = UserDefaults.standard.data(forKey: cacheKey(accountID)), let cache = try? JSONDecoder().decode(Cache.self, from: data) else { return }
        communities = cache.communities; details = cache.details; lastLoadedAt = cache.savedAt
    }
    private func save(accountID: String) {
        guard !accountID.isEmpty else { return }
        let cache = Cache(communities: communities, details: details, savedAt: Date())
        UserDefaults.standard.set(try? JSONEncoder().encode(cache), forKey: cacheKey(accountID))
    }
    private func displayMessage(_ error: Error) -> String {
        let value = error.localizedDescription
        return value == "training.community.error" ? LanguageStore.localizedString("training.community.error") : value
    }

    private func isCancellationError(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled { return true }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
            return isCancellationError(underlying)
        }
        return false
    }
}
