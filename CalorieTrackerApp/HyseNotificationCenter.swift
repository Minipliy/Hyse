import Foundation
import SwiftUI
import Combine
@preconcurrency import UserNotifications

struct HyseNotificationOpenRequest: Equatable, Sendable {
    let type: HyseNotificationKind?
    let communityID: String?
    let workoutID: String?

    init(userInfo: [AnyHashable: Any]) {
        type = (userInfo["type"] as? String).flatMap(HyseNotificationKind.init(rawValue:))
            ?? ((userInfo["destination"] as? String) == "training-monthly-report" ? .monthlyTrainingReport : nil)
        communityID = userInfo["community_id"] as? String
        workoutID = userInfo["workout_id"] as? String
    }
}

nonisolated enum HyseNotificationKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case hyseUpdate = "hyse_update"
    case communityNews = "community_news"
    case workoutLike = "workout_like"
    case workoutComment = "workout_comment"
    case friendRequest = "friend_request"
    case friendAccepted = "friend_accepted"
    case motivation
    case foodLogReminder = "food_log_reminder"
    case waterReminder = "water_reminder"
    case plannedTraining = "planned_training"
    case missingDataReminder = "missing_data_reminder"
    case monthlyTrainingReport = "monthly_training_report"

    var id: String { rawValue }
    var localizationKey: String { "notifications.category.\(rawValue)" }
    var symbol: String {
        switch self {
        case .hyseUpdate: "sparkles"
        case .communityNews: "megaphone.fill"
        case .workoutLike: "heart.fill"
        case .workoutComment: "bubble.left.fill"
        case .friendRequest: "person.badge.plus"
        case .friendAccepted: "person.2.fill"
        case .motivation: "sparkle"
        case .foodLogReminder: "fork.knife"
        case .waterReminder: "drop.fill"
        case .plannedTraining: "calendar.badge.clock"
        case .missingDataReminder: "checklist"
        case .monthlyTrainingReport: "chart.bar.xaxis"
        }
    }
}

nonisolated struct HyseNotification: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let type: HyseNotificationKind
    let actorUsername: String
    let actorName: String?
    let actorAvatar: String?
    let actorAvatarURL: String?
    let title: String
    let body: String
    let communityID: String?
    let communityName: String?
    let workoutID: String?
    let workoutName: String?
    let isReply: Bool?
    var isRead: Bool
    let created: String

    enum CodingKeys: String, CodingKey {
        case id, type, title, body, created
        case actorUsername = "actor_username", actorName = "actor_name", actorAvatar = "actor_avatar", actorAvatarURL = "actor_avatar_url"
        case communityID = "community_id", communityName = "community_name"
        case workoutID = "workout_id", workoutName = "workout_name", isReply = "is_reply", isRead = "is_read"
    }

    var date: Date? {
        Self.fractionalFormatter.date(from: created) ?? ISO8601DateFormatter().date(from: created)
    }
    private static let fractionalFormatter: ISO8601DateFormatter = {
        let value = ISO8601DateFormatter(); value.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return value
    }()
}

actor HyseNotificationService {
    static let shared = HyseNotificationService()
    private let baseURL = HyseConfiguration.serverURL
    enum RequestError: Error, Sendable {
        case invalidURL
        case invalidResponse
        case httpStatus(Int)
        case decoding
    }
    private struct ListResponse: Decodable { let items: [HyseNotification]; let unreadCount: Int; enum CodingKeys: String, CodingKey { case items; case unreadCount = "unread_count" } }
    private struct ReadResponse: Decodable { let read: Bool }

    func list(token: String) async throws -> ([HyseNotification], Int) {
        let response: ListResponse = try await request(path: "/api/hyse/notifications", method: "GET", token: token, body: nil)
        return (response.items, response.unreadCount)
    }

    func markRead(id: String, token: String) async throws {
        let _: ReadResponse = try await request(path: "/api/hyse/notifications/\(id)/read", method: "POST", token: token, body: [:])
    }

    func markAllRead(token: String) async throws {
        let _: ReadResponse = try await request(path: "/api/hyse/notifications/read-all", method: "POST", token: token, body: [:])
    }

    func updatePreferences(settings: UserSettingsStore, token: String) async {
        let body = await MainActor.run {
            [
                "community_news": settings.communityNewsNotificationsEnabled ? "true" : "false",
                "workout_likes": settings.workoutLikeNotificationsEnabled ? "true" : "false",
                "workout_comments": settings.workoutCommentNotificationsEnabled ? "true" : "false",
                "friend_activity": settings.friendActivityNotificationsEnabled ? "true" : "false"
            ]
        }
        let _: ReadResponse? = try? await request(path: "/api/hyse/notification-preferences", method: "POST", token: token, body: body)
    }

    private func request<T: Decodable>(path: String, method: String, token: String, body: [String: String]?) async throws -> T {
        guard let url = URL(string: baseURL + path) else { throw RequestError.invalidURL }
        var request = URLRequest(url: url); request.httpMethod = method; request.timeoutInterval = 12
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body { request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.httpBody = try JSONEncoder().encode(body) }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw RequestError.invalidResponse }
        guard (200...299).contains(http.statusCode) else { throw RequestError.httpStatus(http.statusCode) }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw RequestError.decoding
        }
    }
}

@MainActor
final class HyseNotificationCenterStore: ObservableObject {
    enum LoadError: Equatable { case connection, service }

    @Published private(set) var items: [HyseNotification] = []
    @Published private(set) var unreadCount = 0
    @Published private(set) var isLoading = false
    @Published private(set) var loadError: LoadError?
    @Published private(set) var pendingOpenRequest: HyseNotificationOpenRequest?
    private var accountID = ""
    private var lastNetworkLoadAt: Date?
    private var activeLoadID: UUID?
    private var serverUnreadCount = 0
    private let localReadKey = "hyse_local_notification_center_read_v1"
    private let clearedOldNotificationsKey = "hyse_notification_center_cleared_v1"
    private let localPrefixes: [(String, HyseNotificationKind)] = [
        ("hyse.motivation.", .motivation),
        ("hyse.food-log.", .foodLogReminder),
        ("hyse.water.", .waterReminder),
        ("hyse.planned-training.", .plannedTraining),
        ("hyse.missing-data.", .missingDataReminder),
        ("hyse.training.monthly-report", .monthlyTrainingReport)
    ]

    func load(auth: AuthManager, trainingStore: TrainingStore, force: Bool = false) async {
        clearOldDeliveredNotificationsIfNeeded()
        guard auth.isLoggedIn, !auth.token.isEmpty else { items = []; unreadCount = 0; serverUnreadCount = 0; accountID = ""; lastNetworkLoadAt = nil; loadError = nil; activeLoadID = nil; isLoading = false; return }
        await waitForSessionRefresh(auth)
        guard !Task.isCancelled else { return }
        guard auth.isLoggedIn, !auth.token.isEmpty else { items = []; unreadCount = 0; serverUnreadCount = 0; accountID = ""; lastNetworkLoadAt = nil; loadError = nil; activeLoadID = nil; isLoading = false; return }
        if accountID != auth.accountID {
            accountID = auth.accountID
            items = []
            serverUnreadCount = 0
            unreadCount = 0
            lastNetworkLoadAt = nil
            loadError = nil
            activeLoadID = nil
            isLoading = false
            restore(accountID: accountID)
        }
        await refreshLocalItems(workouts: trainingStore.completedWorkouts)
        guard !Task.isCancelled else { return }
        if !force, let lastNetworkLoadAt, Date().timeIntervalSince(lastNetworkLoadAt) < 300 { return }
        guard activeLoadID == nil else { return }
        let loadID = UUID()
        activeLoadID = loadID
        let requestedAccountID = auth.accountID
        isLoading = items.isEmpty
        defer {
            if activeLoadID == loadID { activeLoadID = nil; isLoading = false }
        }
        do {
            let result = try await HyseNotificationService.shared.list(token: auth.token)
            guard activeLoadID == loadID, !Task.isCancelled, auth.isLoggedIn, auth.accountID == requestedAccountID else { return }
            items = result.0; serverUnreadCount = result.1; loadError = nil; lastNetworkLoadAt = Date(); await refreshLocalItems(workouts: trainingStore.completedWorkouts)
            guard activeLoadID == loadID, auth.accountID == requestedAccountID else { return }
            save(accountID: requestedAccountID)
        } catch let error as HyseNotificationService.RequestError {
            // A restored token can expire while the app is launching. Refresh
            // once only for an explicit auth failure, then retry the feed with
            // the new token. Network and decoding errors remain visible.
            guard case .httpStatus(let status) = error, [401, 403].contains(status) else {
                guard activeLoadID == loadID, auth.accountID == requestedAccountID, !Task.isCancelled else { return }
                loadError = .service
                return
            }
            await auth.refreshSession(force: true)
            guard activeLoadID == loadID, !Task.isCancelled, auth.accountID == requestedAccountID else { return }
            guard auth.isLoggedIn else {
                loadError = .service
                return
            }
            do {
                let result = try await HyseNotificationService.shared.list(token: auth.token)
                guard activeLoadID == loadID, !Task.isCancelled, auth.isLoggedIn, auth.accountID == requestedAccountID else { return }
                items = result.0; serverUnreadCount = result.1; loadError = nil; lastNetworkLoadAt = Date(); await refreshLocalItems(workouts: trainingStore.completedWorkouts)
                guard activeLoadID == loadID, auth.accountID == requestedAccountID else { return }
                save(accountID: requestedAccountID)
            } catch {
                guard activeLoadID == loadID, auth.accountID == requestedAccountID, !Self.isCancellation(error) else { return }
                loadError = Self.isConnectionError(error) ? .connection : .service
            }
        } catch {
            guard activeLoadID == loadID, auth.accountID == requestedAccountID, !Self.isCancellation(error) else { return }
            loadError = Self.isConnectionError(error) ? .connection : .service
        }
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if Task.isCancelled || error is CancellationError { return true }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled { return true }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error { return isCancellation(underlying) }
        return false
    }

    private static func isConnectionError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain { return true }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error { return isConnectionError(underlying) }
        return false
    }

    private func waitForSessionRefresh(_ auth: AuthManager) async {
        // AuthManager refreshes a restored session in parallel with the first
        // view render. Avoid sending the old token to the notification route.
        for _ in 0..<30 {
            guard !Task.isCancelled else { return }
            guard auth.isRefreshingSession else { return }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    func markRead(_ item: HyseNotification, auth: AuthManager, trainingStore: TrainingStore) async {
        guard !item.isRead else { return }
        if let index = items.firstIndex(where: { $0.id == item.id }) { items[index].isRead = true }
        if item.id.hasPrefix("local:") {
            let identifier = String(item.id.dropFirst("local:".count))
            var readIDs = localReadIDs(); readIDs.insert(identifier); saveLocalReadIDs(readIDs)
            unreadCount = max(0, unreadCount - 1)
            return
        }
        serverUnreadCount = max(0, serverUnreadCount - 1); unreadCount = serverUnreadCount + localUnreadCount
        do { try await HyseNotificationService.shared.markRead(id: item.id, token: auth.token); save(accountID: auth.accountID) }
        catch { await load(auth: auth, trainingStore: trainingStore, force: true) }
    }

    func markAllRead(auth: AuthManager, trainingStore: TrainingStore) async {
        items = items.map { value in var copy = value; copy.isRead = true; return copy }
        serverUnreadCount = 0; unreadCount = 0
        saveLocalReadIDs(Set(localItems.map { String($0.id.dropFirst("local:".count)) }))
        do { try await HyseNotificationService.shared.markAllRead(token: auth.token); save(accountID: auth.accountID) }
        catch { await load(auth: auth, trainingStore: trainingStore, force: true) }
    }

    func requestOpen(userInfo: [AnyHashable: Any]) {
        pendingOpenRequest = HyseNotificationOpenRequest(userInfo: userInfo)
    }

    func takePendingOpenRequest() -> HyseNotificationOpenRequest? {
        defer { pendingOpenRequest = nil }
        return pendingOpenRequest
    }

    private struct Cache: Codable { let items: [HyseNotification]; let unreadCount: Int }
    private func cacheKey(_ id: String) -> String { "hyse_notification_center_\(id)_v2" }
    private func clearOldDeliveredNotificationsIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: clearedOldNotificationsKey) else { return }
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        UserDefaults.standard.set(true, forKey: clearedOldNotificationsKey)
    }
    private func restore(accountID: String) {
        guard let data = UserDefaults.standard.data(forKey: cacheKey(accountID)), let cache = try? JSONDecoder().decode(Cache.self, from: data) else { return }
        items = cache.items; serverUnreadCount = cache.unreadCount; unreadCount = cache.unreadCount
    }
    private func save(accountID: String) {
        let serverItems = items.filter { !$0.id.hasPrefix("local:") }
        UserDefaults.standard.set(try? JSONEncoder().encode(Cache(items: serverItems, unreadCount: serverUnreadCount)), forKey: cacheKey(accountID))
    }

    private var localItems: [HyseNotification] { items.filter { $0.id.hasPrefix("local:") } }
    private var localUnreadCount: Int { localItems.filter { !$0.isRead }.count }

    private func refreshLocalItems(workouts: [WorkoutLog]) async {
        let requestedAccountID = accountID
        let delivered = await UNUserNotificationCenter.current().deliveredNotifications()
        guard accountID == requestedAccountID else { return }
        let readIDs = localReadIDs()
        let values = delivered.compactMap { notification -> HyseNotification? in
            guard let kind = localPrefixes.first(where: { notification.request.identifier.hasPrefix($0.0) })?.1,
                  kind != .monthlyTrainingReport else { return nil }
            let identifier = notification.request.identifier
            let eventID = "\(identifier)|\(Self.iso8601.string(from: notification.date))"
            return HyseNotification(
                id: "local:\(eventID)", type: kind, actorUsername: "", actorName: nil, actorAvatar: nil, actorAvatarURL: nil,
                title: notification.request.content.title, body: notification.request.content.body,
                communityID: nil, communityName: nil, workoutID: nil, workoutName: nil, isReply: nil,
                isRead: readIDs.contains(eventID), created: Self.iso8601.string(from: notification.date)
            )
        }
        items = items.filter { !$0.id.hasPrefix("local:") } + values
        if let report = monthlyReportNotification(workouts: workouts, readIDs: readIDs) {
            items.append(report)
        }
        items.sort { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        unreadCount = serverUnreadCount + localUnreadCount
    }

    private func monthlyReportNotification(workouts: [WorkoutLog], readIDs: Set<String>) -> HyseNotification? {
        guard !accountID.isEmpty else { return nil }
        let calendar = Calendar.autoupdatingCurrent
        guard let currentMonth = calendar.dateInterval(of: .month, for: Date())?.start,
              let reportMonth = calendar.date(byAdding: .month, value: -1, to: currentMonth),
              let reportInterval = calendar.dateInterval(of: .month, for: reportMonth),
              workouts.contains(where: { reportInterval.contains($0.completedAt ?? $0.startedAt) }) else { return nil }

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM"
        let eventID = "monthly-report:\(accountID):\(formatter.string(from: reportMonth))"
        return HyseNotification(
            id: "local:\(eventID)", type: .monthlyTrainingReport,
            actorUsername: "", actorName: nil, actorAvatar: nil, actorAvatarURL: nil,
            title: "", body: "", communityID: nil, communityName: nil,
            workoutID: nil, workoutName: nil, isReply: nil,
            isRead: readIDs.contains(eventID), created: Self.iso8601.string(from: currentMonth)
        )
    }

    private func localReadIDs() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: localReadKey) ?? [])
    }

    private func saveLocalReadIDs(_ values: Set<String>) {
        UserDefaults.standard.set(Array(values), forKey: localReadKey)
    }

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return formatter
    }()
}

struct HyseNotificationCenterView: View {
    private enum NotificationFilter: String, CaseIterable, Identifiable {
        case all, updates, communities, friends, reminders
        var id: String { rawValue }
        var localizationKey: String { "notifications.filter.\(rawValue)" }
        var symbol: String {
            switch self {
            case .all: "tray.full"
            case .updates: "sparkles"
            case .communities: "megaphone.fill"
            case .friends: "person.2.fill"
            case .reminders: "clock.badge"
            }
        }
    }

    @EnvironmentObject private var language: LanguageStore
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var store: HyseNotificationCenterStore
    @EnvironmentObject private var communityStore: GymCommunityStore
    @EnvironmentObject private var trainingStore: TrainingStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var social = TrainingSocialStore()
    @State private var selectedFilter = NotificationFilter.all
    @State private var selectedCommunity: GymCommunity?
    @State private var selectedWorkout: FriendWorkout?
    @State private var showingFriends = false
    @State private var showingMonthlyReport = false
    private func t(_ key: String, _ arguments: CVarArg...) -> String { language.text(key, arguments) }
    private var visibleItems: [HyseNotification] {
        store.items.filter { item in
            switch selectedFilter {
            case .all: true
            case .updates: item.type == .hyseUpdate
            case .communities: item.type == .communityNews
            case .friends: [.workoutLike, .workoutComment, .friendRequest, .friendAccepted].contains(item.type)
            case .reminders: [.motivation, .foodLogReminder, .waterReminder, .plannedTraining, .missingDataReminder, .monthlyTrainingReport].contains(item.type)
            }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if !auth.isLoggedIn {
                    HyseEmptyState(icon: "bell.slash", title: t("notifications.account_required"), message: t("notifications.account_required_message"))
                        .listRowBackground(Color.clear)
                } else {
                    categoryPicker
                    if let error = store.loadError {
                        HyseStatusBanner(
                            title: t(error == .connection ? "notifications.connection_title" : "notifications.error_title"),
                            message: t(error == .connection
                                ? (store.items.isEmpty ? "notifications.connection_empty" : "notifications.connection_cached")
                                : "notifications.error"),
                            style: error == .connection ? .offline : .warning,
                            actionTitle: t("content.retry"),
                            action: { Task { await store.load(auth: auth, trainingStore: trainingStore, force: true) } }
                        )
                            .listRowBackground(Color.clear)
                    }
                    if store.isLoading && store.items.isEmpty {
                        ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear)
                    } else if visibleItems.isEmpty && store.loadError == nil {
                        HyseEmptyState(icon: "bell", title: t("notifications.empty"), message: t("notifications.empty_message"))
                            .listRowBackground(Color.clear)
                    } else {
                        ForEach(visibleItems) { item in notificationRow(item) }
                    }
                }
            }
            .hyseForm()
            .navigationTitle(t("notifications.title"))
            .navigationDestination(isPresented: $showingMonthlyReport) {
                TrainingMonthlyReportView(store: trainingStore, month: latestCompletedReportMonth)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.subheadline.weight(.bold))
                            .frame(width: 36, height: 36)
                            .background(HyseColor.elevatedSurface, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(t("notifications.close"))
                }
                ToolbarItem(placement: .confirmationAction) {
                    if store.unreadCount > 0 {
                        Button(t("notifications.mark_all_read")) { Task { await store.markAllRead(auth: auth, trainingStore: trainingStore) } }
                    }
                }
            }
            .refreshable { await store.load(auth: auth, trainingStore: trainingStore, force: true) }
            // The notification center is a deliberate entry point for fresh
            // server state. Do not reuse the dashboard's short-lived cache
            // here, otherwise a newly published Gym Community news post can
            // remain invisible for several minutes after opening the center.
            .task { await store.load(auth: auth, trainingStore: trainingStore, force: true) }
            .task { await openPendingTargetIfNeeded() }
            .onChange(of: store.pendingOpenRequest) { _, _ in
                Task { await openPendingTargetIfNeeded() }
            }
        }
        // The list's pull-to-refresh otherwise captures downward drags. A clear,
        // deliberate swipe can now close the sheet from anywhere in the center.
        .simultaneousGesture(notificationCenterDismissGesture, including: .all)
        .presentationDragIndicator(.visible)
        .sheet(item: $selectedCommunity) { community in
            NavigationStack {
                GymCommunityDetailView(store: communityStore, social: social, trainingStore: trainingStore, initialCommunity: community)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(t("training.close")) { selectedCommunity = nil }
                        }
                    }
            }
        }
        .sheet(item: $selectedWorkout) { workout in
            NavigationStack {
                FriendWorkoutDetailView(social: social, store: trainingStore, workout: workout)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(t("training.close")) { selectedWorkout = nil }
                        }
                    }
            }
        }
        .sheet(isPresented: $showingFriends) {
            TrainingFriendsView(social: social, store: trainingStore)
        }
    }

    private var notificationCenterDismissGesture: some Gesture {
        DragGesture(minimumDistance: 18, coordinateSpace: .local)
            .onEnded { value in
                let downwardDistance = max(value.translation.height, value.predictedEndTranslation.height)
                let horizontalDistance = abs(value.translation.width)
                guard downwardDistance > 110,
                      downwardDistance > horizontalDistance * 1.35 else { return }
                dismiss()
            }
    }

    private var categoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(NotificationFilter.allCases) { filter in
                    let isSelected = selectedFilter == filter
                    Button {
                        withAnimation(.snappy(duration: 0.24)) {
                            selectedFilter = filter
                        }
                    } label: {
                        HStack(spacing: 9) {
                            Image(systemName: filter.symbol)
                                .font(.system(size: 17, weight: .semibold))
                            if isSelected {
                                Text(t(filter.localizationKey))
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.72)
                                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
                            }
                        }
                        .foregroundStyle(isSelected ? Color(.systemBackground) : Color.secondary)
                        .frame(width: isSelected ? 148 : 48, height: 48)
                        .background(isSelected ? Color.primary : HyseColor.elevatedSurface, in: Capsule())
                        .overlay(Capsule().stroke(isSelected ? Color.primary.opacity(0.8) : HyseColor.border, lineWidth: 0.75))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(t(filter.localizationKey))
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 2)
            .animation(.snappy(duration: 0.24), value: selectedFilter)
        }
        .frame(height: 48)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 8, trailing: 0))
    }

    private func notificationRow(_ item: HyseNotification) -> some View {
        let copy = notificationCopy(for: item)
        return Button { Task { await store.markRead(item, auth: auth, trainingStore: trainingStore); await openTarget(for: item) } } label: {
            HStack(alignment: .top, spacing: HyseSpacing.medium) {
                ZStack {
                    Circle().fill(HyseColor.accent.opacity(0.12))
                    Image(systemName: item.type.symbol).foregroundStyle(HyseColor.accent)
                }.frame(width: 42, height: 42)
                VStack(alignment: .leading, spacing: 4) {
                    Text(copy.title).font(.subheadline.weight(item.isRead ? .medium : .bold)).foregroundStyle(.primary)
                    if !copy.body.isEmpty { Text(copy.body).font(.caption).foregroundStyle(.secondary).lineLimit(3) }
                    if let date = item.date { Text(date, style: .relative).font(.caption2).foregroundStyle(.tertiary) }
                }
                Spacer(minLength: 4)
                if !item.isRead { Circle().fill(HyseColor.accent).frame(width: 9, height: 9).padding(.top, 5) }
            }.padding(.vertical, 5).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private func notificationCopy(for item: HyseNotification) -> (title: String, body: String) {
        let preferredName = item.actorName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let username = item.actorUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        let actor = !preferredName.isEmpty ? preferredName : (username.isEmpty ? t("notifications.training.someone") : username)
        let currentWorkoutName = item.workoutName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let workoutName = currentWorkoutName.isEmpty && item.type == .workoutLike
            ? item.body.trimmingCharacters(in: .whitespacesAndNewlines)
            : currentWorkoutName

        switch item.type {
        case .workoutLike:
            return (workoutName.isEmpty
                    ? t("notifications.training.workout_like_generic", actor)
                    : t("notifications.training.workout_like", actor, workoutName), "")
        case .workoutComment:
            let isReply = item.isReply == true
            let title = workoutName.isEmpty
                ? t(isReply ? "notifications.training.workout_reply_generic" : "notifications.training.workout_comment_generic", actor)
                : t(isReply ? "notifications.training.workout_reply" : "notifications.training.workout_comment", actor, workoutName)
            return (title, item.body)
        case .friendRequest:
            return (t("notifications.training.friend_request", actor), "")
        case .friendAccepted:
            return (t("notifications.training.friend_accepted", actor), "")
        case .monthlyTrainingReport:
            let month = latestCompletedReportMonth.formatted(.dateTime.month(.wide).locale(language.locale))
            return (t("training.monthly_report.ready_title", month), t("training.monthly_report.ready_subtitle"))
        default:
            return (item.title.isEmpty ? t(item.type.localizationKey) : item.title, item.body)
        }
    }

    private var latestCompletedReportMonth: Date {
        let calendar = Calendar.autoupdatingCurrent
        let currentMonth = calendar.dateInterval(of: .month, for: Date())?.start ?? Date()
        return calendar.date(byAdding: .month, value: -1, to: currentMonth) ?? currentMonth
    }

    private func openPendingTargetIfNeeded() async {
        guard let request = store.takePendingOpenRequest() else { return }
        if let communityID = request.communityID {
            await communityStore.loadDetail(id: communityID, auth: auth, force: true)
            selectedCommunity = communityStore.community(communityID)
        } else if let workoutID = request.workoutID {
            selectedWorkout = await social.loadDetail(id: workoutID, auth: auth)
        } else if request.type == .friendRequest || request.type == .friendAccepted {
            await social.load(auth: auth, force: true)
            showingFriends = true
        } else if request.type == .monthlyTrainingReport {
            showingMonthlyReport = true
        }
    }

    private func openTarget(for item: HyseNotification) async {
        if let communityID = item.communityID {
            await communityStore.loadDetail(id: communityID, auth: auth, force: true)
            selectedCommunity = communityStore.community(communityID)
        } else if let workoutID = item.workoutID {
            selectedWorkout = await social.loadDetail(id: workoutID, auth: auth)
        } else if item.type == .friendRequest || item.type == .friendAccepted {
            await social.load(auth: auth, force: true)
            showingFriends = true
        } else if item.type == .monthlyTrainingReport {
            showingMonthlyReport = true
        }
    }
}
