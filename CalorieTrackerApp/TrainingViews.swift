import SwiftUI
import UIKit
import PhotosUI
import AVFoundation
import UniformTypeIdentifiers
import CoreTransferable
import Charts
import Combine

/// Notification preferences are opt-in at the moment a user joins a new
/// social space. The system alert still remains under iOS' control; if it is
/// denied we leave all switches untouched.
@MainActor
enum SocialNotificationDefaults {
    static func enable(
        communityNews: Bool = false,
        friendActivity: Bool = false,
        workoutLikes: Bool = false,
        workoutComments: Bool = false,
        settings: UserSettingsStore,
        auth: AuthManager
    ) async -> Bool {
        guard await CommunityPushNotificationManager.shared.requestAndRegister(auth: auth) else { return false }
        if communityNews { settings.communityNewsNotificationsEnabled = true }
        if friendActivity { settings.friendActivityNotificationsEnabled = true }
        if workoutLikes { settings.workoutLikeNotificationsEnabled = true }
        if workoutComments { settings.workoutCommentNotificationsEnabled = true }
        await HyseNotificationService.shared.updatePreferences(settings: settings, token: auth.token)
        return true
    }
}

enum TrainingRootSection: String, CaseIterable, Identifiable {
    case friends, training, profile
    var id: String { rawValue }
    var titleKey: String {
        switch self {
        case .friends: "training.social.home"
        case .training: "training.title"
        case .profile: "app_tabs.profile"
        }
    }
    var symbol: String {
        switch self {
        case .friends: "person.2.fill"
        case .training: "figure.strengthtraining.traditional"
        case .profile: "person.crop.circle.fill"
        }
    }
}

struct TrainingRootView: View {
    private enum FeedEntry: Identifiable {
        case own(WorkoutLog)
        case shared(FriendWorkout)

        var id: String {
            switch self {
            case .own(let workout): "own:\(workout.id)"
            case .shared(let workout): "shared:\(workout.id)"
            }
        }

        var date: Date {
            switch self {
            case .own(let workout): workout.completedAt ?? workout.startedAt
            case .shared(let workout): workout.date ?? .distantPast
            }
        }
    }

    @EnvironmentObject private var language: LanguageStore
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var settings: UserSettingsStore
    @EnvironmentObject private var notificationCenter: HyseNotificationCenterStore
    @EnvironmentObject private var premium: PremiumAccessStore
    @ObservedObject var store: TrainingStore
    @StateObject private var social = TrainingSocialStore()
    @Binding var selectedSection: TrainingRootSection
    let isActive: Bool
    let showsActiveWorkoutBar: Bool
    let openSettings: (() -> Void)?
    @State private var showingActiveWorkout = false
    @State private var openedActiveWorkoutFromBar = false
    @State private var showingExerciseLibrary = false
    @State private var showingRoutineBuilder = false
    @State private var showingHevyImporter = false
    @State private var showingHevyImportGuide = false
    @State private var openHevyImporterAfterGuide = false
    @State private var isImportingHevy = false
    @State private var importMessage: String?
    @State private var importFailed = false
    @State private var showingFriends = false
    @State private var showingUsername = false
    @State private var showingProfileEditor = false
    @State private var showingSuggestedRoutines = false
    @State private var showingMyRoutines = true
    @State private var draggedRoutineID: UUID?
    @State private var routinePreviewOrder: [UUID]?
    @State private var routineHoverTargetID: UUID?
    @State private var profileMetric = TrainingProfileMetric.duration
    @State private var selectedProfileWeek: Date?
    @State private var showingNotifications = false
    @State private var showingTrainingPremium = false
    @State private var cachedProfileMetrics: [TrainingWeekMetric] = []
    @State private var selectedWorkoutActions: FriendWorkout?
    @State private var isPreparingWorkoutAction = false
    @State private var workoutActionMessage: String?
    @State private var workoutForEditing: WorkoutLog?
    @State private var workoutForSharing: WorkoutLog?
    @State private var sharedWorkoutForSharing: FriendWorkout?
    @State private var pendingSharedWorkoutForSharing: FriendWorkout?
    @State private var workoutPendingDeletion: WorkoutLog?
    @State private var workoutPendingSocialFeedID: String?
    @State private var selectedRoutineActions: WorkoutRoutine?
    @State private var routineForSharing: WorkoutRoutine?
    @State private var routineForEditing: WorkoutRoutine?
    @State private var routinePendingDeletion: WorkoutRoutine?
    @State private var showingMonthlyReport = false
    @State private var lastViewedMonthlyReportID = ""

    private func t(_ key: String, _ arguments: CVarArg...) -> String { language.text(key, arguments) }
    private var routineCreationRequiresPremium: Bool {
        !premium.hasTraining && store.routines.count >= TrainingStore.freeRoutineLimit
    }
    private var displayedRoutines: [WorkoutRoutine] {
        guard let routinePreviewOrder,
              Set(routinePreviewOrder) == Set(store.routines.map(\.id)) else { return store.routines }
        let byID = Dictionary(uniqueKeysWithValues: store.routines.map { ($0.id, $0) })
        return routinePreviewOrder.compactMap { byID[$0] }
    }

    private var friendsFeed: [FeedEntry] {
        let own = store.completedWorkouts
        let ownRemoteIDs = Set(own.compactMap(\.remoteID))
        let shared = social.feed.filter { item in
            // A private local workout must never be represented by an older
            // public feed entry while its visibility change is syncing.
            guard item.userID == authManager.accountID || ownRemoteIDs.contains(item.id) else { return true }
            return !own.contains { workout in
                matchesFeedItem(workout, item) && workout.visibility != "public"
            }
        }
        let entries = own.filter { workout in
            workout.visibility != "public"
                || !shared.contains { item in
                    (item.userID == authManager.accountID || ownRemoteIDs.contains(item.id))
                        && matchesFeedItem(workout, item)
                }
        }.map(FeedEntry.own)
        + shared.map(FeedEntry.shared)
        return entries.sorted { $0.date > $1.date }
    }

    private func matchesFeedItem(_ workout: WorkoutLog, _ item: FriendWorkout) -> Bool {
        workout.remoteID == item.id
            || workout.id.uuidString.caseInsensitiveCompare(item.clientID ?? item.id) == .orderedSame
    }

    var body: some View {
        NavigationStack {
            ZStack {
                HyseBackdrop()
                ScrollView {
                    rootContent
                        .padding(.horizontal, HyseSpacing.page)
                        .padding(.top, HyseSpacing.small)
                        .padding(.bottom, HyseSpacing.section)
                }
                .refreshable {
                    store.sync(force: true)
                    await social.load(auth: authManager, force: true)
                }
            }
            .navigationTitle(selectedSection == .profile ? "" : t(selectedSection.titleKey))
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $showingMonthlyReport) {
                TrainingMonthlyReportView(store: store, month: latestCompletedReportMonth)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    if store.hasResolvedPersistenceScope, showsActiveWorkoutBar, let workout = store.activeWorkout {
                        ActiveWorkoutBar(
                            workout: workout,
                            discard: { store.discardActiveWorkout() },
                            open: {
                                openedActiveWorkoutFromBar = true
                                showingActiveWorkout = true
                            }
                        )
                        .padding(.top, HyseSpacing.small)
                        .padding(.bottom, HyseSpacing.medium)
                    }
                    TrainingSectionBar(selection: $selectedSection, title: { t($0.titleKey) })
                        .padding(.horizontal, HyseSpacing.page)
                        .padding(.top, HyseSpacing.small)
                        .padding(.bottom, HyseSpacing.xLarge)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if authManager.isLoggedIn, selectedSection != .profile {
                        Button { showingNotifications = true } label: {
                            Image(systemName: notificationCenter.unreadCount > 0 ? "bell.fill" : "bell")
                                .overlay(alignment: .topTrailing) {
                                    if notificationCenter.unreadCount > 0 { Circle().fill(.red).frame(width: 7, height: 7).offset(x: 3, y: -2) }
                                }
                        }
                        .accessibilityLabel(t("notifications.title"))
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if selectedSection == .training {
                        Button { presentRoutineBuilder() } label: {
                            Image(systemName: "plus")
                                .overlay(alignment: .topTrailing) {
                                    if routineCreationRequiresPremium {
                                        PremiumFeatureIcon(area: .training).offset(x: 9, y: -8)
                                    }
                                }
                        }
                            .accessibilityLabel(t("training.routine.create"))
                    } else if selectedSection == .friends, authManager.isLoggedIn {
                        Button { showingFriends = true } label: { Image(systemName: "person.badge.plus") }
                            .accessibilityLabel(t("training.social.add_friends"))
                    }
                }
                if let openSettings {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: openSettings) {
                            Image(systemName: "gearshape")
                        }
                        .accessibilityLabel(t("content.settings"))
                    }
                }
            }
        }
        .sheet(isPresented: $showingExerciseLibrary) { ExerciseLibraryView(store: store, selectionMode: false) }
        .sheet(isPresented: $showingRoutineBuilder) { RoutineBuilderView(store: store) }
        .sheet(isPresented: $showingTrainingPremium) { PremiumPaywallView(requestedArea: .training) }
        .sheet(item: $selectedRoutineActions) { routine in
            routineActionsSheet(routine)
        }
        .sheet(item: $routineForSharing) { routine in
            RoutineShareView(store: store, routineID: routine.id)
        }
        .sheet(item: $routineForEditing) { routine in
            RoutineBuilderView(store: store, routine: routine)
        }
        .fullScreenCover(isPresented: $showingActiveWorkout, onDismiss: { openedActiveWorkoutFromBar = false }) {
            ActiveWorkoutView(store: store, animateToLatestCompletedExercise: openedActiveWorkoutFromBar)
        }
        .sheet(isPresented: $showingFriends) {
            TrainingFriendsView(social: social, store: store)
                .environmentObject(authManager)
                .environmentObject(language)
                .environmentObject(settings)
        }
        .sheet(isPresented: $showingUsername) { TrainingUsernameView(social: social).environmentObject(authManager).environmentObject(language) }
        .sheet(isPresented: $showingProfileEditor) {
            TrainingProfileEditView(social: social)
                .environmentObject(authManager)
                .environmentObject(language)
        }
        .sheet(isPresented: $showingNotifications) { HyseNotificationCenterView() }
        .sheet(item: $selectedWorkoutActions, onDismiss: {
            if let workout = pendingSharedWorkoutForSharing {
                pendingSharedWorkoutForSharing = nil
                sharedWorkoutForSharing = workout
            }
        }) { workout in
            friendWorkoutActionsSheet(workout)
        }
        .sheet(item: $workoutForEditing) { workout in
            NavigationStack {
                WorkoutCompletionEditor(
                    workout: workout,
                    store: store,
                    onSave: { edited in
                        store.updateCompletedWorkout(edited)
                        workoutForEditing = nil
                        refreshSocialFeedAfterLocalChange()
                    },
                    onDiscard: { workoutForEditing = nil }
                )
            }
        }
        .sheet(item: $workoutForSharing) { workout in
            WorkoutShareComposer(
                workout: workout,
                muscleCounts: WorkoutShareMuscles.counts(for: workout),
                store: store
            )
            .environmentObject(language)
        }
        .sheet(item: $sharedWorkoutForSharing) { workout in
            FriendWorkoutShareLoaderView(workout: workout, social: social, store: store)
                .environmentObject(authManager)
                .environmentObject(language)
        }
        .sheet(isPresented: $showingSuggestedRoutines) {
            SuggestedRoutineBrowserView(store: store)
                .environmentObject(language)
                .environmentObject(premium)
        }
        .sheet(isPresented: $showingHevyImportGuide, onDismiss: {
            guard openHevyImporterAfterGuide else { return }
            openHevyImporterAfterGuide = false
            showingHevyImporter = true
        }) {
            HevyImportGuideView {
                openHevyImporterAfterGuide = true
                showingHevyImportGuide = false
            }
            .environmentObject(language)
        }
        .fileImporter(
            isPresented: $showingHevyImporter,
            allowedContentTypes: [.commaSeparatedText, .plainText],
            allowsMultipleSelection: true,
            onCompletion: importHevyFiles
        )
        .confirmationDialog(
            t("training.feed.delete_title"),
            isPresented: Binding(
                get: { workoutPendingDeletion != nil },
                set: {
                    if !$0 {
                        workoutPendingDeletion = nil
                        workoutPendingSocialFeedID = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button(t("training.feed.delete"), role: .destructive) {
                guard let workout = workoutPendingDeletion else { return }
                store.deleteCompletedWorkout(workout.id)
                social.removeFromFeed(workoutID: workout.id, remoteFeedID: workoutPendingSocialFeedID, accountID: authManager.accountID)
                workoutPendingDeletion = nil
                workoutPendingSocialFeedID = nil
                refreshSocialFeedAfterLocalChange()
            }
            Button(t("app_tabs.cancel"), role: .cancel) {}
        } message: {
            Text(t("training.feed.delete_message"))
        }
        .confirmationDialog(
            t("training.routine.delete_confirm_title"),
            isPresented: Binding(
                get: { routinePendingDeletion != nil },
                set: { if !$0 { routinePendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(t("training.routine.delete_action"), role: .destructive) {
                guard let routine = routinePendingDeletion else { return }
                store.deleteRoutine(routine.id)
                routinePendingDeletion = nil
            }
            Button(t("app_tabs.cancel"), role: .cancel) {}
        } message: {
            Text(t("training.routine.delete_confirm_message"))
        }
        .task(id: "\(isActive)-\(authManager.isLoggedIn)-\(authManager.accountID)-\(selectedSection.rawValue)") {
            guard isActive, authManager.isLoggedIn else { return }
            // Always refresh when the friends home becomes visible. The feed is
            // account-scoped and can change while this root view stays alive;
            // relying on the initial task's freshness window made new friend
            // workouts appear to be missing for up to 15 minutes.
            await social.load(auth: authManager, force: selectedSection == .friends)
        }
        .onAppear { rebuildProfileMetrics(from: store.completedWorkouts) }
        .onChange(of: store.completedWorkouts) { _, workouts in
            rebuildProfileMetrics(from: workouts)
        }
        .onChange(of: store.completedWorkouts.compactMap(\.remoteID)) { _, _ in
            guard isActive, selectedSection == .friends, authManager.isLoggedIn else { return }
            Task { await social.load(auth: authManager, force: true) }
        }
        .onChange(of: selectedSection) { _, section in
            if isActive, section == .friends || section == .profile {
                Task { await social.load(auth: authManager, force: section == .friends) }
            }
        }
        .onChange(of: isActive) { _, active in
            guard active, selectedSection == .friends || selectedSection == .profile else { return }
            Task { await social.load(auth: authManager, force: selectedSection == .friends) }
        }
        .dynamicTypeSize(.small)
    }

    @ViewBuilder private var rootContent: some View {
        switch selectedSection {
        case .friends: friendsContent
        case .training: trainingContent
        case .profile: profileContent
        }
    }

    @ViewBuilder private var friendsContent: some View {
        LazyVStack(alignment: .leading, spacing: HyseSpacing.large) {
            if !authManager.isLoggedIn {
                HyseCard { HyseEmptyState(icon: "person.2", title: t("training.social.account_required"), message: t("training.social.account_required_message")) }
            } else {
                if isMonthlyReportNew {
                    monthlyReportAnnouncement
                }
                if social.username.isEmpty {
                    HyseCard(accent: HyseColor.accent) {
                        Button { showingUsername = true } label: {
                            HStack {
                                Label(t("training.social.create_username"), systemImage: "at")
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                if let error = social.errorMessage {
                    HyseStatusBanner(title: t("training.social.error_title"), message: error, style: .warning, actionTitle: t("content.retry"), action: { Task { await social.load(auth: authManager, force: true) } })
                }
                if !social.requests.isEmpty {
                    sectionHeading(t("training.social.requests"), value: "\(social.requests.count)")
                    ForEach(social.requests) { request in
                        HyseCard {
                            HStack {
                                TrainingProfileLink(userID: request.userID, username: request.username, nickname: request.nickname,
                                                    avatar: request.avatar, avatarURL: request.avatarURL, social: social, store: store) {
                                    HStack {
                                        RemoteProfileAvatarView(userID: request.userID, filename: request.avatar, remoteURL: request.avatarURL, size: 42)
                                        Text("@\(request.username)").font(.headline)
                                    }
                                }
                                Spacer()
                                Button(t("training.social.accept")) { acceptFriend(request) }
                                    .buttonStyle(.borderedProminent)
                            }
                        }
                    }
                }

                NavigationLink {
                            GymCommunityListView(social: social, trainingStore: store)
                } label: {
                    HyseCard(accent: HyseColor.accent) {
                        HStack(spacing: HyseSpacing.large) {
                            HyseIconBadge(icon: "building.2.fill", size: 50)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(t("training.community.title")).font(.title3.bold()).foregroundStyle(.primary)
                                Text(t("training.community.subtitle")).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.subheadline.bold()).foregroundStyle(HyseColor.accent)
                        }
                    }
                }
                .buttonStyle(.plain)

                sectionHeading(t("training.social.friends_workouts"), value: "\(friendsFeed.count)", info: t("info.training.feed"))
                if let workoutActionMessage {
                    HyseStatusBanner(title: nil, message: workoutActionMessage, style: .success)
                }
                if friendsFeed.isEmpty {
                    HyseCard(accent: HyseColor.accent) {
                        HyseEmptyState(icon: "person.2.fill", title: t("training.social.empty_feed"), message: t("training.social.empty_feed_message"), actionTitle: t("training.social.add_friends"), action: { showingFriends = true })
                    }
                } else {
                    ForEach(friendsFeed) { entry in
                        switch entry {
                        case .own(let workout): profileWorkoutRow(workout, showVisibility: true)
                        case .shared(let workout): friendWorkoutRow(workout)
                        }
                    }
                }
            }
        }
    }

    private func acceptFriend(_ request: TrainingFriendConnection) {
        Task {
            guard await social.accept(request, auth: authManager) else { return }
            _ = await SocialNotificationDefaults.enable(
                friendActivity: true,
                workoutLikes: true,
                workoutComments: true,
                settings: settings,
                auth: authManager
            )
        }
    }

    @ViewBuilder private var trainingContent: some View {
        LazyVStack(alignment: .leading, spacing: HyseSpacing.large) {
            syncBanner

            Button {
                _ = store.startEmptyWorkout()
                showingActiveWorkout = true
            } label: {
                HStack(spacing: HyseSpacing.medium) {
                    Image(systemName: "plus")
                        .font(.title2.weight(.medium))
                        .frame(width: 34)
                    Text(t("training.start_empty"))
                        .font(.title3.weight(.semibold))
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, HyseSpacing.large)
                .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
                .background(HyseColor.surface, in: RoundedRectangle(cornerRadius: HyseRadius.card, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(store.activeWorkout != nil)
            .hyseTourTarget(.trainingStart)

            HStack {
                Text(t("training.routines")).font(.title2.bold())
                Spacer()
                Button { presentRoutineBuilder() } label: {
                    Image(systemName: "folder.badge.plus")
                        .font(.title2.weight(.medium))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
                .accessibilityLabel(t("training.routines.new"))
            }

            HStack(spacing: HyseSpacing.medium) {
                compactAction(title: t("training.routines.new"), icon: "list.clipboard") {
                    presentRoutineBuilder()
                }
                compactAction(title: t("training.routines.discover"), icon: "magnifyingglass") {
                    showingSuggestedRoutines = true
                }
            }

            Button {
                withAnimation(HyseMotion.standard) { showingMyRoutines.toggle() }
            } label: {
                HStack(spacing: HyseSpacing.small) {
                    Image(systemName: showingMyRoutines ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.bold))
                    Text(t("training.routines.yours"))
                        .font(.title3.weight(.semibold))
                    Text("(\(store.routines.count))")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showingMyRoutines {
                if store.routines.isEmpty {
                    HyseCard {
                        Text(t("training.routines.empty.message"))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    VStack(spacing: HyseSpacing.large) {
                        ForEach(displayedRoutines) { routine in
                            routineListCard(routine)
                                .opacity(draggedRoutineID == routine.id ? 0.02 : 1)
                                .onDrag {
                                    draggedRoutineID = routine.id
                                    routinePreviewOrder = store.routines.map(\.id)
                                    routineHoverTargetID = nil
                                    ExerciseReorderFeedback.pickedUp()
                                    return NSItemProvider(object: routine.id.uuidString as NSString)
                                } preview: {
                                    routineListCard(routine)
                                        .frame(width: min(UIScreen.main.bounds.width - 2 * HyseSpacing.page, 500))
                                        .scaleEffect(1.02)
                                        .shadow(color: .black.opacity(0.18), radius: 18, y: 10)
                                }
                                .onDrop(of: [.text], delegate: RoutineCardDropDelegate(
                                    targetID: routine.id,
                                    draggedRoutineID: $draggedRoutineID,
                                    previewOrder: $routinePreviewOrder,
                                    hoverTargetID: $routineHoverTargetID,
                                    store: store
                                ))
                        }
                    }
                    .contentShape(Rectangle())
                    .onDrop(of: [.text], delegate: RoutineListDropDelegate(
                        draggedRoutineID: $draggedRoutineID,
                        previewOrder: $routinePreviewOrder,
                        hoverTargetID: $routineHoverTargetID,
                        store: store
                    ))
                }
            }

            NavigationLink { RoutineListView(store: store) } label: {
                Label(t("training.routines.manage_all"), systemImage: "list.bullet.rectangle.portrait").font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity)

            if let last = store.lastWorkout {
                Button { store.repeatWorkout(last); showingActiveWorkout = true } label: {
                    Label(t("training.repeat_last"), systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
                .disabled(store.activeWorkout != nil)
            }
        }
    }

    @ViewBuilder private var profileContent: some View {
        LazyVStack(alignment: .leading, spacing: HyseSpacing.large) {
            if !authManager.isLoggedIn {
                HyseCard { HyseEmptyState(icon: "person.crop.circle.badge.exclamationmark", title: t("training.social.account_required"), message: t("training.social.profile_account_message")) }
            } else {
                VStack(alignment: .leading, spacing: HyseSpacing.medium) {
                    HStack(spacing: HyseSpacing.medium) {
                        Rectangle()
                            .fill(HyseColor.border)
                            .frame(height: 1)
                        Text("HYSE")
                            .font(.caption2.weight(.bold))
                            .tracking(4)
                            .foregroundStyle(.secondary)
                        Rectangle()
                            .fill(HyseColor.border)
                            .frame(height: 1)
                    }
                    .padding(.top, HyseSpacing.xLarge)

                    HStack(alignment: .center, spacing: HyseSpacing.medium) {
                        Button { showingProfileEditor = true } label: {
                            ProfileAvatarView(size: 64, editable: false)
                                .overlay(alignment: .bottomTrailing) {
                                    Image(systemName: "pencil")
                                        .font(.caption.bold())
                                        .foregroundStyle(.white)
                                        .frame(width: 24, height: 24)
                                        .background(HyseColor.accent, in: Circle())
                                        .overlay(Circle().stroke(HyseColor.background, lineWidth: 2))
                                        .offset(x: 3, y: 3)
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(t("training.social.edit_profile"))
                        VStack(alignment: .leading, spacing: HyseSpacing.small) {
                            Button { showingProfileEditor = true } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: HyseSpacing.small) {
                                        Text(social.username.isEmpty ? t("training.social.no_username") : social.username)
                                            .font(.title2.bold())
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.75)
                                        Image(systemName: "pencil")
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(HyseColor.accent)
                                    }
                                    Text(t("training.social.edit_profile"))
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(HyseColor.accent)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(social.username.isEmpty ? t("training.social.no_username") : social.username), \(t("training.social.edit_profile"))")
                            HStack(spacing: HyseSpacing.large) {
                                profileStat(t("training.statistics.workouts"), "\(store.statistics.workoutCount)")
                                NavigationLink {
                                    TrainingConnectionsListView(kind: .friends, social: social, store: store)
                                } label: {
                                    profileConnectionStat(t("training.social.friends"), "\(social.friends.count)")
                                }
                                NavigationLink {
                                    TrainingConnectionsListView(kind: .followers, social: social, store: store)
                                } label: {
                                    profileConnectionStat(t("training.social.followers"), "\(social.friends.count)")
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer(minLength: 0)
                    }
                    if !social.bio.isEmpty {
                        VStack(alignment: .leading, spacing: HyseSpacing.small) {
                            Label(t("training.social.bio"), systemImage: "quote.opening")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(HyseColor.accent)

                            Text(social.bio)
                                .font(.body)
                                .foregroundStyle(.primary)
                                .lineSpacing(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(HyseSpacing.medium)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(HyseColor.elevatedSurface, in: RoundedRectangle(cornerRadius: HyseRadius.control, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: HyseRadius.control, style: .continuous)
                                .stroke(HyseColor.border, lineWidth: 0.5)
                        }
                    }
                }
            }

            if let importMessage {
                HyseStatusBanner(title: t(importFailed ? "training.hevy_import.failed_title" : "training.hevy_import.success_title"), message: importMessage, style: importFailed ? .warning : .success, actionTitle: t("common.ok"), action: { self.importMessage = nil })
            }

            WeeklyRoutinePlanView(store: store) { routine in
                guard store.activeWorkout == nil else { return }
                _ = store.start(routine: routine)
                showingActiveWorkout = true
            }

            profileChart

            Text(t("training.profile.manage_training")).font(.title3.bold())
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: HyseSpacing.medium) {
                NavigationLink { TrainingStatisticsView(store: store) } label: { dashboardTile(t("training.profile.all_statistics"), "chart.xyaxis.line") }
                Button { showingExerciseLibrary = true } label: { dashboardTile(t("training.exercises"), "dumbbell") }
                NavigationLink { TrainingHistoryView(store: store) } label: { dashboardTile(t("training.history"), "clock.arrow.circlepath") }
                NavigationLink { TrainingCalendarView(store: store) } label: { dashboardTile(t("training.calendar"), "calendar") }
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: HyseSpacing.xSmall) {
                Button { showingHevyImportGuide = true } label: {
                    dashboardTile(t("training.hevy_import.title"), "square.and.arrow.down")
                }
                .buttonStyle(.plain)
                .disabled(isImportingHevy)
                Text(t("training.hevy_import.subtitle"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if isImportingHevy { HStack(spacing: HyseSpacing.small) { ProgressView(); Text(t("training.hevy_import.processing")).foregroundStyle(.secondary) } }

            sectionHeading(t("training.profile.recent_workouts"), value: "\(store.completedWorkouts.count)", info: t("info.training.recent_workouts"))
            if store.completedWorkouts.isEmpty {
                HyseCard { Text(t("training.empty.message")).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading) }
            } else {
                ForEach(store.completedWorkouts.prefix(6)) { workout in
                    profileWorkoutRow(workout)
                }
            }
        }
    }

    private func profileWorkoutRow(_ workout: WorkoutLog, showVisibility: Bool = false) -> some View {
        VStack {
            VStack(alignment: .leading, spacing: HyseSpacing.medium) {
                HStack(spacing: HyseSpacing.medium) {
                    ProfileAvatarView(size: 46, editable: false)
                    VStack(alignment: .leading, spacing: HyseSpacing.xSmall) {
                        Text(social.username.isEmpty ? t("app_tabs.profile") : social.username)
                            .font(.headline)
                        Text((workout.completedAt ?? workout.startedAt).formatted(.relative(presentation: .named)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Menu {
                        Button {
                            workoutForEditing = workout
                        } label: {
                            Label(t("training.feed.edit"), systemImage: "pencil")
                        }
                        Button {
                            workoutForSharing = workout
                        } label: {
                            Label(t("training.feed.share"), systemImage: "square.and.arrow.up")
                        }
                        Button {
                            store.createRoutine(from: workout)
                        } label: {
                            Label(t("training.feed.save_as_routine"), systemImage: "square.and.arrow.down")
                        }
                        Button {
                            store.repeatWorkout(workout)
                            showingActiveWorkout = true
                        } label: {
                            Label(t("training.repeat"), systemImage: "arrow.counterclockwise")
                        }
                        .disabled(store.activeWorkout != nil)
                        Button(role: .destructive) {
                            workoutPendingSocialFeedID = nil
                            workoutPendingDeletion = workout
                        } label: {
                            Label(t("training.feed.delete"), systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.headline)
                            .frame(width: 40, height: 40)
                            .contentShape(Rectangle())
                    }
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(t("training.feed.actions"))
                }

                if showVisibility {
                    HStack(alignment: .top, spacing: HyseSpacing.medium) {
                        NavigationLink {
                            WorkoutSummaryView(workout: workout, store: store, username: social.username)
                        } label: {
                            VStack(alignment: .leading, spacing: HyseSpacing.small) {
                                Text(workout.name)
                                    .font(.title3.bold())
                                    .foregroundStyle(.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                                if !workout.notes.isEmpty {
                                    Text(workout.notes)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                Text("\(formatDuration(workout.duration)) · \(formattedVolume(workout.totalVolume))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        WorkoutMediaView(localFilename: workout.mediaLocalFilename, compact: true, compactSize: 80)
                    }
                } else {
                    HStack(alignment: .top, spacing: HyseSpacing.medium) {
                        NavigationLink {
                            WorkoutSummaryView(workout: workout, store: store, username: social.username)
                        } label: {
                            VStack(alignment: .leading, spacing: HyseSpacing.small) {
                                Text(workout.name)
                                    .font(.title3.bold())
                                    .foregroundStyle(.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                                if !workout.notes.isEmpty {
                                    Text(workout.notes)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                if workout.mediaLocalFilename != nil {
                                    Text("\(formatDuration(workout.duration)) · \(formattedVolume(workout.totalVolume))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    HStack(spacing: HyseSpacing.section) {
                                        feedMetric(t("training.duration"), formatDuration(workout.duration))
                                        feedMetric(t("training.total_volume"), formattedVolume(workout.totalVolume))
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        if workout.mediaLocalFilename != nil {
                            WorkoutMediaView(localFilename: workout.mediaLocalFilename, compact: true, compactSize: 80)
                        }
                    }
                }

                NavigationLink {
                    WorkoutSummaryView(workout: workout, store: store, username: social.username)
                } label: {
                    VStack(alignment: .leading, spacing: HyseSpacing.medium) {
                        Divider()

                        VStack(alignment: .leading, spacing: HyseSpacing.medium) {
                            ForEach(Array(workout.exercises.prefix(3))) { exercise in
                                HStack(spacing: HyseSpacing.medium) {
                                    ExerciseMovementVisual(exercise: exerciseSnapshot(exercise), height: 44)
                                    Text(exercisePreviewText(exercise))
                                        .font(.subheadline)
                                        .foregroundStyle(.primary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            if workout.exercises.count > 3 {
                                Text(t("training.feed.more_exercises", workout.exercises.count - 3))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                HStack(spacing: HyseSpacing.section) {
                    if authManager.isLoggedIn {
                        NavigationLink {
                            WorkoutCommentsLoaderView(social: social, store: store, workoutID: workout.remoteID ?? workout.id.uuidString.lowercased())
                                .environmentObject(authManager)
                                .environmentObject(language)
                        } label: {
                            Label(t("training.social.comments"), systemImage: "bubble.left")
                        }
                    }
                    Button {
                        workoutForSharing = workout
                    } label: {
                        Label(t("training.feed.share"), systemImage: "square.and.arrow.up")
                    }
                }
                .font(.subheadline)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                if showVisibility, let workoutID = workout.remoteID {
                    commentsPreview(for: workoutID)
                }
            }
        }
        .padding(.vertical, HyseSpacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Divider()
        }
        .task(id: workout.remoteID) {
            guard showVisibility, authManager.isLoggedIn, let workoutID = workout.remoteID else { return }
            _ = await social.loadDetail(id: workoutID, auth: authManager)
        }
    }

    private func friendWorkoutRow(_ item: FriendWorkout) -> some View {
        let localWorkout = store.completedWorkouts.first { matchesFeedItem($0, item) }
        return VStack {
            VStack(alignment: .leading, spacing: HyseSpacing.medium) {
                HStack(spacing: HyseSpacing.small) {
                    TrainingProfileLink(userID: item.userID, username: item.username, nickname: item.nickname,
                                        avatar: item.avatar, avatarURL: item.avatarURL, social: social, store: store) {
                        HStack(spacing: HyseSpacing.medium) {
                            RemoteProfileAvatarView(userID: item.userID, filename: item.avatar, remoteURL: item.avatarURL, size: 46)
                            VStack(alignment: .leading, spacing: HyseSpacing.xSmall) {
                                Text(item.displayName).font(.headline)
                                if let date = item.date { Text(date.formatted(.relative(presentation: .named))).font(.caption).foregroundStyle(.secondary) }
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    Button {
                        selectedWorkoutActions = item
                        Task { await social.loadDetail(item, auth: authManager) }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.headline)
                            .frame(width: 40, height: 40)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(t("training.feed.actions"))
                }
                HStack(alignment: .top, spacing: HyseSpacing.medium) {
                    NavigationLink {
                        FriendWorkoutDetailView(social: social, store: store, workout: item)
                            .environmentObject(authManager)
                            .environmentObject(language)
                    } label: {
                        VStack(alignment: .leading, spacing: HyseSpacing.small) {
                            Text(item.name)
                                .font(.title3.bold())
                                .fixedSize(horizontal: false, vertical: true)
                            if !(localWorkout?.notes ?? item.notes).isEmpty {
                                Text(localWorkout?.notes ?? item.notes)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Text("\(formatDuration(item.duration)) · \(formattedVolume(item.totalVolume))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    WorkoutMediaView(localFilename: localWorkout?.mediaLocalFilename, remoteURL: item.mediaURL, compact: true, compactSize: 80)
                }
                if let snapshot = social.detail(for: item.id)?.snapshot {
                    Divider()
                    VStack(alignment: .leading, spacing: HyseSpacing.medium) {
                        ForEach(Array(snapshot.exercises.prefix(3))) { exercise in
                            HStack(spacing: HyseSpacing.medium) {
                                ExerciseMovementVisual(exercise: exerciseSnapshot(exercise), height: 52)
                                Text(exercisePreviewText(exercise))
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        if snapshot.exercises.count > 3 {
                            Text(t("training.feed.more_exercises", snapshot.exercises.count - 3))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                }
                Divider()
                HStack(spacing: HyseSpacing.large) {
                    Button { Task { await social.toggleLike(item.id, auth: authManager) } } label: {
                        Label("\(item.likeCount)", systemImage: item.likedByMe ? "hand.thumbsup.fill" : "hand.thumbsup")
                            .foregroundStyle(item.likedByMe ? HyseColor.accent : .secondary)
                    }
                    NavigationLink {
                        WorkoutCommentsPage(social: social, store: store, workout: item)
                            .environmentObject(authManager)
                            .environmentObject(language)
                    } label: {
                        Label("\(item.commentCount)", systemImage: "bubble.left")
                    }
                    Button { sharedWorkoutForSharing = item } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    Spacer()
                }
                .font(.title3)
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
                WorkoutLikesSummary(social: social, store: store, workout: item)
                commentsPreview(for: item.id)
            }
        }
        .padding(.vertical, HyseSpacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Divider()
        }
        .task {
            await social.loadDetail(item, auth: authManager)
        }
    }

    @ViewBuilder
    private func commentsPreview(for workoutID: String) -> some View {
        if let comments = social.detail(for: workoutID)?.comments, !comments.isEmpty {
            VStack(alignment: .leading, spacing: HyseSpacing.small) {
                ForEach(Array(comments.prefix(2))) { comment in
                    let parent = comment.parentID.flatMap { parentID in comments.first(where: { $0.id == parentID }) }
                    HStack(alignment: .top, spacing: HyseSpacing.small) {
                        TrainingProfileLink(userID: comment.userID, username: comment.username, nickname: comment.nickname,
                                            avatar: comment.avatar, avatarURL: comment.avatarURL, social: social, store: store) {
                            RemoteProfileAvatarView(userID: comment.userID, filename: comment.avatar, remoteURL: comment.avatarURL, size: 28)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            TrainingProfileLink(userID: comment.userID, username: comment.username, nickname: comment.nickname,
                                                avatar: comment.avatar, avatarURL: comment.avatarURL, social: social, store: store) {
                                Text(comment.displayName).font(.subheadline.bold())
                            }
                            if let parent {
                                TrainingProfileLink(userID: parent.userID, username: parent.username, nickname: parent.nickname,
                                                    avatar: parent.avatar, avatarURL: parent.avatarURL, social: social, store: store) {
                                    Text("↳ @\(parent.username)").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Text(comment.body)
                                .font(.subheadline)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(.top, HyseSpacing.xSmall)
        }
    }

    private func exerciseSnapshot(_ log: WorkoutExerciseLog) -> TrainingExercise {
        store.exercises.first(where: { $0.id == log.exerciseID }) ?? TrainingExercise(
            id: log.exerciseID,
            nameKey: "custom",
            englishName: log.exerciseNameSnapshot,
            germanName: log.exerciseGermanNameSnapshot,
            descriptionKey: "",
            techniqueKey: "",
            type: log.exerciseTypeSnapshot,
            equipment: log.equipmentSnapshot,
            primaryMuscles: log.primaryMusclesSnapshot,
            secondaryMuscles: log.secondaryMusclesSnapshot,
            isCustom: true,
            isFavorite: false,
            updatedAt: Date()
        )
    }

    private func exerciseDisplayName(_ exercise: WorkoutExerciseLog) -> String {
        language.isGerman && !exercise.exerciseGermanNameSnapshot.isEmpty
            ? exercise.exerciseGermanNameSnapshot
            : exercise.exerciseNameSnapshot
    }

    private func exercisePreviewText(_ exercise: WorkoutExerciseLog) -> String {
        let count = TrainingSetStatistics.count(exercise, halveUnilateral: settings.countUnilateralSetsAsHalf)
        let key = count == 1 ? "training.feed.exercise_set" : "training.feed.exercise_sets"
        return t(key, TrainingSetStatistics.formatted(count, locale: language.locale), exerciseDisplayName(exercise))
    }

    private func friendWorkoutActionsSheet(_ item: FriendWorkout) -> some View {
        let isOwnWorkout = isOwnedWorkout(item)
        return NavigationStack {
            VStack(spacing: 0) {
                Capsule()
                    .fill(Color.secondary.opacity(0.55))
                    .frame(width: 38, height: 5)
                    .padding(.top, 10)
                    .padding(.bottom, HyseSpacing.large)

                VStack(spacing: 0) {
                    Button {
                        pendingSharedWorkoutForSharing = item
                        selectedWorkoutActions = nil
                    } label: {
                        workoutActionRow(t("training.feed.share"), icon: "square.and.arrow.up")
                    }
                    Divider().padding(.leading, 58)
                    Button { performWorkoutAction(.saveRoutine, item: item) } label: {
                        workoutActionRow(t("training.feed.save_as_routine"), icon: "square.and.arrow.down")
                    }
                    Divider().padding(.leading, 58)
                    Button { performWorkoutAction(.copy, item: item) } label: {
                        workoutActionRow(t("training.feed.copy"), icon: "square.on.square")
                    }
                    if isOwnWorkout {
                        Divider().padding(.leading, 58)
                        Button { performWorkoutAction(.edit, item: item) } label: {
                            workoutActionRow(t("training.feed.edit"), icon: "pencil")
                        }
                        Divider().padding(.leading, 58)
                        Button(role: .destructive) { performWorkoutAction(.delete, item: item) } label: {
                            workoutActionRow(t("training.feed.delete"), icon: "xmark", color: .red)
                        }
                    }
                }
                .background(HyseColor.elevatedSurface, in: RoundedRectangle(cornerRadius: HyseRadius.card, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: HyseRadius.card, style: .continuous)
                        .stroke(HyseColor.border)
                }
                .padding(.horizontal, HyseSpacing.page)
                .buttonStyle(.plain)

                if isPreparingWorkoutAction {
                    HStack(spacing: HyseSpacing.small) {
                        ProgressView()
                        Text(t("training.feed.preparing"))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, HyseSpacing.medium)
                }
                Spacer(minLength: HyseSpacing.medium)
            }
            .background(HyseBackdrop())
            .toolbar(.hidden, for: .navigationBar)
        }
        .presentationDetents([.height(isOwnWorkout ? 500 : 340)])
        .presentationDragIndicator(.hidden)
    }

    private func routineActionsSheet(_ routine: WorkoutRoutine) -> some View {
        NavigationStack {
            VStack(spacing: 0) {
                Capsule()
                    .fill(Color.secondary.opacity(0.55))
                    .frame(width: 38, height: 5)
                    .padding(.top, 10)
                    .padding(.bottom, HyseSpacing.medium)

                Text(routine.name)
                    .font(.headline)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, HyseSpacing.page)
                    .padding(.bottom, HyseSpacing.large)

                VStack(spacing: 0) {
                    Button {
                        selectedRoutineActions = nil
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(250))
                            routineForSharing = routine
                        }
                    } label: {
                        workoutActionRow(t("training.routine.share"), icon: "square.and.arrow.up")
                    }
                    Divider().padding(.leading, 58)
                    Menu {
                        Button(t("training.routine.no_planned_day")) {
                            moveRoutine(routine, to: nil)
                            selectedRoutineActions = nil
                        }
                        ForEach(1...7, id: \.self) { weekday in
                            Button(t("training.routine.weekday.\(weekday)")) {
                                moveRoutine(routine, to: weekday)
                                selectedRoutineActions = nil
                            }
                        }
                    } label: {
                        workoutActionRow(t("training.routine.move_day"), icon: "calendar")
                    }
                    Divider().padding(.leading, 58)
                    Button {
                        store.duplicateRoutine(routine)
                        selectedRoutineActions = nil
                    } label: {
                        workoutActionRow(t("training.routine.duplicate_action"), icon: "square.on.square")
                    }
                    Divider().padding(.leading, 58)
                    Button {
                        selectedRoutineActions = nil
                        Task {
                            try? await Task.sleep(for: .milliseconds(250))
                            routineForEditing = routine
                        }
                    } label: {
                        workoutActionRow(t("training.routine.edit"), icon: "pencil")
                    }
                    Divider().padding(.leading, 58)
                    Button(role: .destructive) {
                        selectedRoutineActions = nil
                        Task {
                            try? await Task.sleep(for: .milliseconds(250))
                            routinePendingDeletion = routine
                        }
                    } label: {
                        workoutActionRow(t("training.routine.delete_action"), icon: "xmark", color: .red)
                    }
                }
                .background(HyseColor.elevatedSurface, in: RoundedRectangle(cornerRadius: HyseRadius.card, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: HyseRadius.card, style: .continuous)
                        .stroke(HyseColor.border)
                }
                .padding(.horizontal, HyseSpacing.page)
                .buttonStyle(.plain)

                Spacer(minLength: HyseSpacing.medium)
            }
            .background(HyseBackdrop())
            .toolbar(.hidden, for: .navigationBar)
        }
        .presentationDetents([.height(445)])
        .presentationDragIndicator(.hidden)
    }

    private func moveRoutine(_ routine: WorkoutRoutine, to weekday: Int?) {
        var updated = routine
        updated.plannedWeekday = weekday
        _ = store.saveRoutine(updated)
    }

    private func workoutActionRow(_ title: String, icon: String, color: Color = .primary) -> some View {
        HStack(spacing: HyseSpacing.large) {
            Image(systemName: icon)
                .font(.title3)
                .frame(width: 28)
            Text(title)
                .font(.body)
            Spacer()
        }
        .foregroundStyle(color)
        .padding(.horizontal, HyseSpacing.large)
        .frame(height: 68)
        .contentShape(Rectangle())
    }

    private enum FeedWorkoutAction {
        case saveRoutine, copy, edit, delete
    }

    private func performWorkoutAction(_ action: FeedWorkoutAction, item: FriendWorkout) {
        guard !isPreparingWorkoutAction else { return }
        isPreparingWorkoutAction = true
        Task {
            await social.loadDetail(item, auth: authManager)
            guard let snapshot = social.detail(for: item.id)?.snapshot else {
                isPreparingWorkoutAction = false
                selectedWorkoutActions = nil
                workoutActionMessage = t("training.feed.details_unavailable")
                return
            }
            isPreparingWorkoutAction = false
            selectedWorkoutActions = nil
            switch action {
            case .saveRoutine:
                store.createRoutine(from: snapshot)
                workoutActionMessage = t("training.feed.routine_saved")
            case .copy:
                guard store.activeWorkout == nil else {
                    workoutActionMessage = t("training.feed.active_workout_exists")
                    return
                }
                store.repeatWorkout(snapshot)
                showingActiveWorkout = true
            case .edit:
                guard isOwnedWorkout(item) else { return }
                workoutForEditing = snapshot
            case .delete:
                guard isOwnedWorkout(item) else { return }
                workoutPendingSocialFeedID = item.id
                workoutPendingDeletion = snapshot
            }
        }
    }

    /// Older feed records can be missing `user_id`. Once their snapshot has
    /// loaded we can still safely recognize the user's own local workout and
    /// expose the edit/delete actions instead of leaving an undeletable card.
    private func isOwnedWorkout(_ item: FriendWorkout) -> Bool {
        if item.userID == authManager.accountID { return true }
        guard let snapshot = social.detail(for: item.id)?.snapshot else { return false }
        return store.completedWorkouts.contains(where: { $0.id == snapshot.id })
    }

    private func refreshSocialFeedAfterLocalChange() {
        Task {
            try? await Task.sleep(for: .seconds(1))
            await social.load(auth: authManager, force: true)
        }
    }

    private var latestCompletedReportMonth: Date {
        let calendar = Calendar.autoupdatingCurrent
        let currentMonth = calendar.dateInterval(of: .month, for: Date())?.start ?? Date()
        return calendar.date(byAdding: .month, value: -1, to: currentMonth) ?? currentMonth
    }

    private var monthlyReportID: String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: latestCompletedReportMonth)
    }

    private var monthlyReportMonthName: String {
        latestCompletedReportMonth.formatted(.dateTime.month(.wide).locale(language.locale))
    }

    private var monthlyReportWorkoutCount: Int {
        guard let interval = Calendar.autoupdatingCurrent.dateInterval(of: .month, for: latestCompletedReportMonth) else { return 0 }
        return store.completedWorkouts.filter {
            let date = $0.completedAt ?? $0.startedAt
            return interval.contains(date)
        }.count
    }

    private var monthlyReportAcknowledgementKey: String {
        "lastViewedMonthlyTrainingReport_v2_\(authManager.accountID)"
    }

    private var isMonthlyReportNew: Bool {
        monthlyReportWorkoutCount > 0
            && lastViewedMonthlyReportID != "\(authManager.accountID):\(monthlyReportID)"
            && UserDefaults.standard.string(forKey: monthlyReportAcknowledgementKey) != monthlyReportID
    }

    private func markMonthlyReportViewed() {
        lastViewedMonthlyReportID = "\(authManager.accountID):\(monthlyReportID)"
        UserDefaults.standard.set(monthlyReportID, forKey: monthlyReportAcknowledgementKey)
    }

    private var monthlyReportAnnouncement: some View {
        HyseCard(accent: HyseColor.accent) {
            VStack(alignment: .leading, spacing: HyseSpacing.medium) {
                monthlyReportArtwork
                    .frame(maxWidth: .infinity)
                    .frame(height: 130)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: HyseSpacing.xSmall) {
                    Text(t("training.monthly_report.ready_title", monthlyReportMonthName))
                        .font(.title3.bold())
                        .foregroundStyle(.primary)
                    Text(t("training.monthly_report.ready_subtitle"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    showingMonthlyReport = true
                    markMonthlyReportViewed()
                    if let notice = notificationCenter.items.first(where: { $0.id.hasPrefix("local:monthly-report:") && !$0.isRead }) {
                        Task { await notificationCenter.markRead(notice, auth: authManager, trainingStore: store) }
                    }
                } label: {
                    Text(t("training.monthly_report.show"))
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(HyseColor.accent, in: RoundedRectangle(cornerRadius: HyseRadius.control))
                }
                .buttonStyle(.plain)

                Button { markMonthlyReportViewed() } label: {
                    Text(t("training.monthly_report.dismiss"))
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(HyseColor.controlSurface, in: RoundedRectangle(cornerRadius: HyseRadius.control))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var monthlyReportArtwork: some View {
        ZStack {
            reportArtworkCard("dumbbell.fill", size: 72)
                .rotationEffect(.degrees(-18))
                .offset(x: -48, y: 8)
            reportArtworkCard("calendar", size: 72)
                .rotationEffect(.degrees(18))
                .offset(x: 48, y: 8)
            reportArtworkCard("chart.bar.fill", size: 82)
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "arrow.up.right")
                        .font(.caption.bold())
                        .foregroundStyle(HyseColor.accent)
                        .padding(8)
                }
                .offset(y: -7)
        }
    }

    private func reportArtworkCard(_ symbol: String, size: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(HyseColor.elevatedSurface)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.36, weight: .medium))
                    .foregroundStyle(HyseColor.accent)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(HyseColor.border, lineWidth: 1)
            }
            .frame(width: size, height: size * 1.15)
    }

    private var profileChart: some View {
        let points = cachedProfileMetrics
        let selectedPoint = selectedProfilePoint(in: points)
        return VStack(alignment: .leading, spacing: HyseSpacing.medium) {
            HStack(alignment: .firstTextBaseline) {
                Text(profileChartSummary(for: selectedPoint ?? points.last)).font(.title3.bold())
                Spacer()
                HyseInfoButton(
                    title: t(profileMetric.titleKey),
                    message: t("info.training.profile_chart")
                )
                Text(t(profileMetric.titleKey)).font(.subheadline).foregroundStyle(HyseColor.accent)
            }
            Chart {
                ForEach(points) { point in
                    BarMark(
                        x: .value("Week", point.week, unit: .weekOfYear),
                        y: .value("Value", point.value(for: profileMetric))
                    )
                    .foregroundStyle(selectedPoint == nil || selectedPoint?.id == point.id ? HyseColor.accent : HyseColor.accent.opacity(0.34))
                    .cornerRadius(3)
                    .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                        if selectedPoint?.id == point.id {
                            profileChartSelectionLabel(point)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .weekOfYear, count: 3)) { _ in
                    AxisGridLine().foregroundStyle(.clear)
                    AxisTick().foregroundStyle(.secondary)
                    AxisValueLabel(format: .dateTime.month(.abbreviated))
                }
            }
            .chartYAxis { AxisMarks(position: .leading) }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { gesture in
                                    selectProfilePoint(at: gesture.location, proxy: proxy, geometry: geometry, points: points)
                                }
                        )
                }
            }
            .transaction { transaction in transaction.animation = nil }
            .frame(height: 132)

            HStack(spacing: HyseSpacing.small) {
                ForEach(TrainingProfileMetric.allCases) { metric in
                    Button {
                        selectedProfileWeek = nil
                        profileMetric = metric
                    } label: {
                        Text(t(metric.titleKey))
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, HyseSpacing.small)
                            .background(profileMetric == metric ? HyseColor.accent : HyseColor.elevatedSurface, in: Capsule())
                            .foregroundStyle(profileMetric == metric ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(HyseSpacing.medium)
        .background(HyseColor.surface, in: RoundedRectangle(cornerRadius: HyseRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: HyseRadius.card, style: .continuous)
                .stroke(HyseColor.border, lineWidth: 1)
        }
    }

    private func rebuildProfileMetrics(from workouts: [WorkoutLog]) {
        let calendar = Calendar.current
        let currentWeek = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? calendar.startOfDay(for: Date())
        guard let firstWeek = calendar.date(byAdding: .weekOfYear, value: -11, to: currentWeek),
              let rangeEnd = calendar.date(byAdding: .weekOfYear, value: 1, to: currentWeek) else {
            cachedProfileMetrics = []
            return
        }

        var buckets: [Date: (duration: Double, volume: Double, repetitions: Int)] = [:]
        for workout in workouts {
            let date = workout.completedAt ?? workout.startedAt
            guard date >= firstWeek, date < rangeEnd,
                  let week = calendar.dateInterval(of: .weekOfYear, for: date)?.start else { continue }
            var bucket = buckets[week] ?? (0, 0, 0)
            bucket.duration += workout.duration
            bucket.volume += workout.totalVolume
            bucket.repetitions += workout.totalReps
            buckets[week] = bucket
        }

        cachedProfileMetrics = (-11...0).compactMap { offset in
            guard let week = calendar.date(byAdding: .weekOfYear, value: offset, to: currentWeek) else { return nil }
            let bucket = buckets[week] ?? (0, 0, 0)
            return TrainingWeekMetric(
                week: week,
                durationHours: bucket.duration / 3_600,
                volumeTonnes: bucket.volume / 1_000,
                repetitions: Double(bucket.repetitions)
            )
        }
    }

    private func profileChartSummary(for point: TrainingWeekMetric?) -> String {
        switch profileMetric {
        case .duration: return formatDuration((point?.durationHours ?? 0) * 3_600)
        case .volume: return String(format: "%.1f t", point?.volumeTonnes ?? 0)
        case .repetitions: return "\(Int(point?.repetitions ?? 0)) \(t("training.reps"))"
        }
    }

    private func selectedProfilePoint(in points: [TrainingWeekMetric]) -> TrainingWeekMetric? {
        guard let selectedProfileWeek else { return nil }
        return points.min {
            abs($0.week.timeIntervalSince(selectedProfileWeek)) < abs($1.week.timeIntervalSince(selectedProfileWeek))
        }
    }

    private func selectProfilePoint(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy, points: [TrainingWeekMetric]) {
        let date = ChartBarSelection.date(
            at: location, proxy: proxy, geometry: geometry,
            bars: points.map { ($0.week, $0.value(for: profileMetric)) }, unit: .weekOfYear
        )
        guard selectedProfileWeek != date else { return }
        selectedProfileWeek = date
    }

    private func profileChartSelectionLabel(_ point: TrainingWeekMetric) -> some View {
        VStack(spacing: 2) {
            Text(profileMetricValue(point))
                .font(.caption.weight(.bold))
                .monospacedDigit()
            Text(point.week.formatted(.dateTime.day().month(.abbreviated).year().locale(language.locale)))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, HyseSpacing.medium)
        .padding(.vertical, HyseSpacing.small)
        .background(HyseColor.surface, in: RoundedRectangle(cornerRadius: HyseRadius.small, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: HyseRadius.small, style: .continuous)
                .stroke(.white.opacity(0.14), lineWidth: 0.5)
        }
    }

    private func profileMetricValue(_ point: TrainingWeekMetric) -> String {
        switch profileMetric {
        case .duration: return formatDuration(point.durationHours * 3_600)
        case .volume: return String(format: "%.2f t", point.volumeTonnes)
        case .repetitions: return "\(Int(point.repetitions)) \(t("training.reps"))"
        }
    }

    private func sectionHeading(_ title: String, value: String? = nil, info: String? = nil) -> some View {
        HStack {
            Text(title).font(.title3.bold())
            Spacer()
            if let value { Text(value).font(.subheadline).foregroundStyle(.secondary) }
            if let info {
                HyseInfoButton(title: title, message: info)
            }
        }
    }

    private func presentRoutineBuilder() {
        if routineCreationRequiresPremium {
            showingTrainingPremium = true
        } else {
            showingRoutineBuilder = true
        }
    }

    private func compactAction(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HyseCard {
                HStack(spacing: HyseSpacing.medium) {
                    HyseIconBadge(icon: icon, size: 36)
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .layoutPriority(1)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }

    private func routineListCard(_ routine: WorkoutRoutine) -> some View {
        routineCardLayout(routine)
            .accessibilityHint(t("training.routine.reorder_hint"))
    }

    private func routineCardLayout(_ routine: WorkoutRoutine) -> some View {
        VStack(alignment: .leading, spacing: HyseSpacing.medium) {
            HStack(alignment: .top, spacing: HyseSpacing.small) {
                NavigationLink {
                    RoutineDetailView(store: store, routineID: routine.id)
                } label: {
                    VStack(alignment: .leading, spacing: HyseSpacing.small) {
                        Text(routine.name)
                            .font(.title3.bold())
                            .foregroundStyle(.primary)
                        Text(routineExerciseSummary(routine))
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button { selectedRoutineActions = routine } label: {
                    Image(systemName: "ellipsis")
                        .font(.headline.weight(.bold))
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
                .accessibilityLabel(t("training.routine.actions"))

            }

            Button {
                _ = store.start(routine: routine)
                showingActiveWorkout = true
            } label: {
                Text(t("training.routine.start"))
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(HyseColor.accent, in: RoundedRectangle(cornerRadius: HyseRadius.control, style: .continuous))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(store.activeWorkout != nil)
        }
        .padding(HyseSpacing.large)
        .background(HyseColor.surface, in: RoundedRectangle(cornerRadius: HyseRadius.card, style: .continuous))
    }

    private func routineFilterLabel(_ title: String, icon: String) -> some View {
        HStack(spacing: HyseSpacing.small) {
            Image(systemName: icon)
            Text(title).lineLimit(1)
            Spacer(minLength: 0)
            Image(systemName: "chevron.down").font(.caption2.bold())
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.primary)
        .padding(.horizontal, HyseSpacing.medium)
        .frame(maxWidth: .infinity, minHeight: 42)
        .background(HyseColor.surface, in: RoundedRectangle(cornerRadius: HyseRadius.control, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: HyseRadius.control, style: .continuous).stroke(HyseColor.border))
    }

    private func dashboardTile(_ title: String, _ icon: String) -> some View {
        HStack(spacing: HyseSpacing.medium) {
            Image(systemName: icon)
                .font(.body.weight(.medium))
                .frame(width: 26)
            Text(title)
                .font(.body.weight(.medium))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, HyseSpacing.medium)
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .background(HyseColor.surface, in: RoundedRectangle(cornerRadius: HyseRadius.control, style: .continuous))
    }

    private var weeklyTrainingStreakCard: some View {
        let stats = store.statistics
        let isActive = stats.trainedThisWeek
        let color = isActive ? HyseColor.streakFire : Color.secondary
        return HStack(spacing: HyseSpacing.large) {
            Image(systemName: isActive ? "flame.fill" : "flame")
                .font(.system(size: 25, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 48, height: 48)
                .background(color.opacity(isActive ? 0.14 : 0.08), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(t("training.weekly_streak.title"))
                    .font(.headline)
                Text(t(isActive ? "training.weekly_streak.completed" : "training.weekly_streak.pending"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: HyseSpacing.small)
            VStack(alignment: .trailing, spacing: 1) {
                Text("\(stats.currentStreak)")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(isActive ? color : .primary)
                Text(t("training.weekly_streak.weeks"))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(HyseSpacing.large)
        .hyseGlassSurface(radius: HyseRadius.card, tint: isActive ? color : nil)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(t("training.weekly_streak.accessibility", stats.currentStreak))
    }

    private func profileStat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: HyseSpacing.xSmall) {
            Text(title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Text(value).font(.title3.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func profileConnectionStat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: HyseSpacing.xSmall) {
            HStack(spacing: 3) {
                Text(title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.caption2.bold())
                    .foregroundStyle(.tertiary)
            }
            Text(value).font(.title3.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityHint(t("training.social.open_connections"))
    }

    private func feedMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: HyseSpacing.xSmall) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline)
        }
    }

    private func routineExerciseSummary(_ routine: WorkoutRoutine) -> String {
        let names = routine.exercises.prefix(5).map { $0.exercise.displayName(isGerman: language.isGerman) }
        return names.isEmpty ? t("training.routine.exercise_count", 0) : names.joined(separator: ", ")
    }

    private func formattedVolume(_ kilograms: Double) -> String {
        kilograms >= 1_000 ? String(format: "%.1f t", kilograms / 1_000) : "\(Int(kilograms)) kg"
    }

    private func formatDuration(_ seconds: Double) -> String {
        let minutes = max(0, Int(seconds) / 60)
        return minutes >= 60 ? "\(minutes / 60) h \(minutes % 60) min" : "\(minutes) min"
    }

    @ViewBuilder private var syncBanner: some View {
        switch store.syncState {
        case .offline: HyseStatusBanner(title: t("content.offline"), message: t("training.sync.offline"), style: .offline, actionTitle: t("content.retry"), action: { store.sync(force: true) })
        case .failed: HyseStatusBanner(title: t("content.sync_pending"), message: t("training.sync.failed"), style: .warning, actionTitle: t("content.retry"), action: { store.sync(force: true) })
        default: EmptyView()
        }
    }

    private func importHevyFiles(_ result: Result<[URL], Error>) {
        guard case let .success(urls) = result, !urls.isEmpty else {
            if case .failure = result {
                importFailed = true
                importMessage = t("training.hevy_import.failed_message")
            }
            return
        }
        isImportingHevy = true
        importMessage = nil
        Task {
            do {
                var files: [HevyImportFile] = []
                for url in urls {
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    files.append(HevyImportFile(name: url.lastPathComponent, data: try Data(contentsOf: url)))
                }
                let parsed = try await Task.detached(priority: .userInitiated) {
                    try HevyImportService.parse(files)
                }.value
                let summary = store.applyHevyImport(parsed)
                importFailed = false
                importMessage = t(
                    "training.hevy_import.success_message",
                    summary.importedWorkouts,
                    summary.importedRoutines,
                    summary.importedExercises,
                    summary.importedMeasurements,
                    summary.skippedWorkouts + summary.skippedRoutines + summary.skippedMeasurements
                )
            } catch {
                importFailed = true
                importMessage = t("training.hevy_import.failed_message")
            }
            isImportingHevy = false
        }
    }
}

private struct HevyImportGuideView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var language: LanguageStore
    let startImport: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: HyseSpacing.large) {
                    HyseCard(accent: HyseColor.accent) {
                        HStack(alignment: .top, spacing: HyseSpacing.medium) {
                            HyseIconBadge(icon: "square.and.arrow.down", size: 48)
                            VStack(alignment: .leading, spacing: HyseSpacing.xSmall) {
                                Text(language.text("training.hevy_import.guide_intro_title"))
                                    .font(.title3.bold())
                                Text(language.text("training.hevy_import.guide_intro_body"))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    guideSection(
                        title: language.text("training.hevy_import.what_title"),
                        icon: "tray.and.arrow.down.fill"
                    ) {
                        guideRow("checkmark.circle.fill", "training.hevy_import.workouts")
                        guideRow("square.on.square", "training.hevy_import.routines")
                        guideRow("dumbbell.fill", "training.hevy_import.exercises_sets")
                        guideRow("scalemass.fill", "training.hevy_import.measurements")
                        guideRow("arrow.triangle.2.circlepath", "training.hevy_import.duplicates")
                    }

                    guideSection(
                        title: language.text("training.hevy_import.how_title"),
                        icon: "list.number"
                    ) {
                        numberedStep(1, "training.hevy_import.step_profile")
                        numberedStep(2, "training.hevy_import.step_export")
                        numberedStep(3, "training.hevy_import.step_files")
                        numberedStep(4, "training.hevy_import.step_select")
                    }

                    HyseStatusBanner(
                        title: language.text("training.hevy_import.not_imported_title"),
                        message: language.text("training.hevy_import.not_imported_body"),
                        style: .information
                    )

                    Button(action: startImport) {
                        Label(language.text("training.hevy_import.choose_files"), systemImage: "doc.badge.plus")
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(HysePrimaryButtonStyle())
                }
                .padding(HyseSpacing.page)
            }
            .background(HyseBackdrop())
            .navigationTitle(language.text("training.hevy_import.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(language.text("app_tabs.cancel")) { dismiss() }
                }
            }
        }
    }

    private func guideSection<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        HyseCard {
            VStack(alignment: .leading, spacing: HyseSpacing.medium) {
                Label(title, systemImage: icon)
                    .font(.headline)
                    .foregroundStyle(HyseColor.accent)
                content()
            }
        }
    }

    private func guideRow(_ icon: String, _ key: String) -> some View {
        Label {
            Text(language.text(key)).font(.subheadline)
        } icon: {
            Image(systemName: icon).foregroundStyle(HyseColor.accent)
        }
    }

    private func numberedStep(_ number: Int, _ key: String) -> some View {
        HStack(alignment: .top, spacing: HyseSpacing.medium) {
            Text("\(number)")
                .font(.caption.bold().monospacedDigit())
                .foregroundStyle(HyseColor.accent)
                .frame(width: 28, height: 28)
                .background(HyseColor.accent.opacity(0.12), in: Circle())
            Text(language.text(key))
                .font(.subheadline)
                .padding(.top, 4)
            Spacer(minLength: 0)
        }
    }
}

private enum TrainingProfileMetric: String, CaseIterable, Identifiable {
    case duration, volume, repetitions
    var id: String { rawValue }
    var titleKey: String {
        switch self {
        case .duration: "training.duration"
        case .volume: "training.total_volume"
        case .repetitions: "training.reps"
        }
    }
}

private struct TrainingWeekMetric: Identifiable {
    let week: Date
    let durationHours: Double
    let volumeTonnes: Double
    let repetitions: Double
    var id: Date { week }
    func value(for metric: TrainingProfileMetric) -> Double {
        switch metric {
        case .duration: durationHours
        case .volume: volumeTonnes
        case .repetitions: repetitions
        }
    }
}

private struct TrainingSectionBar: View {
    @Binding var selection: TrainingRootSection
    let title: (TrainingRootSection) -> String
    @GestureState private var draggedCenterX: CGFloat?

    private let spacing: CGFloat = 4
    private let outerPadding: CGFloat = 7
    private let barHeight: CGFloat = 70
    private let segmentHeight: CGFloat = 56

    @ViewBuilder
    var body: some View {
        fallbackBar
    }

    private var fallbackBar: some View {
        GeometryReader { proxy in
            barContents(width: proxy.size.width)
                .contentShape(Capsule())
                .simultaneousGesture(selectionDrag(width: proxy.size.width))
                .background(HyseColor.surface, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                        .allowsHitTesting(false)
                }
        }
        .frame(height: barHeight)
        .sensoryFeedback(.selection, trigger: selection)
    }

    private func barContents(width: CGFloat) -> some View {
        let metrics = segmentMetrics(width: width)
        return ZStack(alignment: .leading) {
            Capsule()
                .fill(Color.primary.opacity(0.105))
                .overlay {
                    Capsule().stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
                }
                .frame(width: metrics.segmentWidth, height: segmentHeight)
                .offset(x: bubbleLeadingX(metrics: metrics))
                .animation(HyseMotion.quick, value: selection)
                .allowsHitTesting(false)

            sectionLabels
                .padding(.horizontal, outerPadding)
        }
        .frame(height: barHeight)
    }

    private var sectionLabels: some View {
        HStack(spacing: spacing) {
            ForEach(TrainingRootSection.allCases) { section in
                Button {
                    withAnimation(HyseMotion.quick) {
                        selection = section
                    }
                } label: {
                    sectionLabel(section)
                        .hyseTourTarget(tourStep(for: section))
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel(title(section))
                .accessibilityAddTraits(selection == section ? .isSelected : [])
            }
        }
    }

    private func sectionLabel(_ section: TrainingRootSection) -> some View {
        Image(systemName: section.symbol)
            .font(.system(size: 23, weight: .semibold))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(selection == section ? Color.primary : Color.secondary)
            .frame(width: 38, height: 38)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    private func tourStep(for section: TrainingRootSection) -> HyseTourStep {
        switch section {
        case .friends: .trainingFriends
        case .training: .trainingWorkouts
        case .profile: .trainingProfile
        }
    }

    private struct SegmentMetrics {
        let segmentWidth: CGFloat
        let firstCenterX: CGFloat
        let stride: CGFloat
    }

    private func segmentMetrics(width: CGFloat) -> SegmentMetrics {
        let count = CGFloat(TrainingRootSection.allCases.count)
        let contentWidth = max(0, width - outerPadding * 2)
        let segmentWidth = max(0, (contentWidth - spacing * (count - 1)) / count)
        return SegmentMetrics(
            segmentWidth: segmentWidth,
            firstCenterX: outerPadding + segmentWidth / 2,
            stride: segmentWidth + spacing
        )
    }

    private func bubbleLeadingX(metrics: SegmentMetrics) -> CGFloat {
        let sections = TrainingRootSection.allCases
        let index = CGFloat(sections.firstIndex(of: selection) ?? 0)
        let restingCenter = metrics.firstCenterX + index * metrics.stride
        return (draggedCenterX ?? restingCenter) - metrics.segmentWidth / 2
    }

    private func selectionDrag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .local)
            .updating($draggedCenterX) { value, draggedCenterX, _ in
                let metrics = segmentMetrics(width: width)
                let sections = TrainingRootSection.allCases
                let lastCenter = metrics.firstCenterX + CGFloat(sections.count - 1) * metrics.stride
                draggedCenterX = min(max(value.location.x, metrics.firstCenterX), lastCenter)
            }
            .onEnded { value in
                let sections = TrainingRootSection.allCases
                let metrics = segmentMetrics(width: width)
                let lastCenter = metrics.firstCenterX + CGFloat(sections.count - 1) * metrics.stride
                let center = min(max(value.location.x, metrics.firstCenterX), lastCenter)
                let rawIndex = (center - metrics.firstCenterX) / max(metrics.stride, 1)
                let index = min(max(Int(rawIndex.rounded()), 0), sections.count - 1)
                withAnimation(HyseMotion.quick) {
                    selection = sections[index]
                }
            }
    }
}

struct BodyMeasurementHistoryView: View {
    @EnvironmentObject private var language: LanguageStore
    let measurements: [BodyMeasurement]

    var body: some View {
        List {
            ForEach(measurements.sorted { $0.date > $1.date }) { measurement in
                NavigationLink {
                    BodyMeasurementDetailView(measurement: measurement)
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(measurement.date.formatted(.dateTime.day().month().year().locale(language.locale)))
                            .font(.headline)
                        HStack(spacing: 14) {
                            if let weight = measurement.weightKilograms {
                                Label("\(weight.formatted(.number.precision(.fractionLength(0...1)))) kg", systemImage: "scalemass")
                            }
                            if let fat = measurement.bodyFatPercentage {
                                Label("\(fat.formatted(.number.precision(.fractionLength(0...1)))) %", systemImage: "percent")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .hyseForm()
        .navigationTitle(language.text("training.measurements.title"))
    }
}

private struct BodyMeasurementDetailView: View {
    @EnvironmentObject private var language: LanguageStore
    let measurement: BodyMeasurement

    var body: some View {
        List {
            Section {
                if let weight = measurement.weightKilograms {
                    LabeledContent(language.text("training.measurements.weight"), value: "\(weight.formatted(.number.precision(.fractionLength(0...1)))) kg")
                }
                if let fat = measurement.bodyFatPercentage {
                    LabeledContent(language.text("training.measurements.body_fat"), value: "\(fat.formatted(.number.precision(.fractionLength(0...1)))) %")
                }
            }
            if !measurement.centimeters.isEmpty {
                Section(language.text("training.measurements.circumferences")) {
                    ForEach(measurement.centimeters.keys.sorted(), id: \.self) { key in
                        if let value = measurement.centimeters[key] {
                            LabeledContent(language.text("training.measurements.\(key)"), value: "\(value.formatted(.number.precision(.fractionLength(0...1)))) cm")
                        }
                    }
                }
            }
            Section {
                LabeledContent(language.text("training.measurements.source"), value: measurement.source)
            }
        }
        .hyseForm()
        .navigationTitle(measurement.date.formatted(.dateTime.day().month().year().locale(language.locale)))
    }
}
