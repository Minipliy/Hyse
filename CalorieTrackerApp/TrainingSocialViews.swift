import SwiftUI
import UIKit
import PhotosUI
import Charts
import Combine

struct TrainingProfileLink<Label: View>: View {
    @EnvironmentObject private var language: LanguageStore
    let userID: String?
    let username: String
    let nickname: String?
    let avatar: String?
    let avatarURL: String?
    let social: TrainingSocialStore
    let store: TrainingStore
    @ViewBuilder let label: () -> Label

    var body: some View {
        if let userID, !userID.isEmpty {
            NavigationLink {
                TrainingPublicProfileView(
                    initialUser: TrainingSocialUser(
                        id: userID,
                        username: username,
                        nickname: nickname,
                        avatar: avatar,
                        avatarURL: avatarURL
                    ),
                    social: social,
                    store: store
                )
            } label: {
                label()
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(language.text("training.social.open_profile_hint"))
        } else {
            label()
        }
    }
}

struct WorkoutLikesSummary: View {
    @EnvironmentObject private var language: LanguageStore
    @EnvironmentObject private var authManager: AuthManager
    @ObservedObject var social: TrainingSocialStore
    let store: TrainingStore
    let workout: FriendWorkout
    @State private var showingLikes = false

    private var likes: [FriendWorkoutLike] { social.detail(for: workout.id)?.likes ?? [] }
    private var count: Int { social.detail(for: workout.id)?.workout.likeCount ?? workout.likeCount }

    var body: some View {
        if count > 0 {
            Button { showingLikes = true } label: {
                HStack(spacing: HyseSpacing.small) {
                    HStack(spacing: -8) {
                        ForEach(Array(likes.prefix(2))) { liker in
                            RemoteProfileAvatarView(userID: liker.id, filename: liker.avatar, remoteURL: liker.avatarURL, size: 26)
                                .overlay(Circle().stroke(HyseColor.background, lineWidth: 1.5))
                        }
                    }
                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(language.text("training.social.likes_title") + ": " + summary)
            .sheet(isPresented: $showingLikes) {
                WorkoutLikesListView(social: social, store: store, workout: workout)
                    .environmentObject(language)
                    .environmentObject(authManager)
            }
        }
    }

    private var summary: String {
        guard let first = likes.first(where: { $0.id != authManager.accountID }) ?? likes.first else {
            return language.text("training.social.likes_count", [count])
        }
        if count == 1, first.id == authManager.accountID {
            return language.text("training.social.liked_by_you")
        }
        if count == 1 { return language.text("training.social.liked_by_one", [first.username]) }
        return language.text("training.social.liked_by_more", [first.username, count - 1])
    }
}

private struct WorkoutLikesListView: View {
    @EnvironmentObject private var language: LanguageStore
    @EnvironmentObject private var authManager: AuthManager
    @ObservedObject var social: TrainingSocialStore
    let store: TrainingStore
    let workout: FriendWorkout
    @State private var search = ""
    @Environment(\.dismiss) private var dismiss

    private var likes: [FriendWorkoutLike] {
        let all = social.detail(for: workout.id)?.likes ?? []
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return all }
        return all.filter {
            $0.username.localizedCaseInsensitiveContains(query)
                || $0.displayName.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(likes) { liker in
                    TrainingProfileLink(userID: liker.id, username: liker.username, nickname: liker.nickname,
                                        avatar: liker.avatar, avatarURL: liker.avatarURL, social: social, store: store) {
                        HStack(spacing: HyseSpacing.medium) {
                            RemoteProfileAvatarView(userID: liker.id, filename: liker.avatar, remoteURL: liker.avatarURL, size: 42)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(liker.username).font(.headline)
                                if liker.displayName != liker.username {
                                    Text(liker.displayName).font(.subheadline).foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .searchable(text: $search, prompt: language.text("training.social.search_placeholder"))
            .navigationTitle(language.text("training.social.likes_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(language.text("training.close")) { dismiss() }
                }
            }
        }
        .task { await social.loadDetail(workout, auth: authManager, force: true) }
    }
}

struct WorkoutCommentsLoaderView: View {
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var language: LanguageStore
    @ObservedObject var social: TrainingSocialStore
    @ObservedObject var store: TrainingStore
    let workoutID: String
    @State private var workout: FriendWorkout?
    @State private var isLoading = true

    var body: some View {
        Group {
            if let workout {
                WorkoutCommentsPage(social: social, store: store, workout: workout)
            } else if isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = social.errorMessage {
                HyseStatusBanner(title: nil, message: error, style: .warning,
                                 actionTitle: language.text("content.retry"), action: { Task { await load() } })
                    .padding(HyseSpacing.page)
            }
        }
        .task(id: workoutID) { await load() }
    }

    private func load() async {
        isLoading = true
        workout = await social.loadDetail(id: workoutID, auth: authManager)
        isLoading = false
    }
}

private struct WorkoutCommentRow: Identifiable {
    let comment: FriendWorkoutComment
    let depth: Int
    var id: String { comment.id }
}

private func orderedWorkoutCommentRows(_ comments: [FriendWorkoutComment]) -> [WorkoutCommentRow] {
    let ids = Set(comments.map(\.id))
    let children = Dictionary(grouping: comments.filter { $0.parentID != nil }, by: { $0.parentID ?? "" })
    var rows: [WorkoutCommentRow] = []
    var visited = Set<String>()
    func append(_ comment: FriendWorkoutComment, depth: Int) {
        guard visited.insert(comment.id).inserted else { return }
        rows.append(WorkoutCommentRow(comment: comment, depth: depth))
        for child in children[comment.id] ?? [] { append(child, depth: depth + 1) }
    }
    for comment in comments where comment.parentID == nil || !ids.contains(comment.parentID ?? "") {
        append(comment, depth: 0)
    }
    for comment in comments { append(comment, depth: 0) }
    return rows
}

struct WorkoutCommentsPage: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var language: LanguageStore
    @EnvironmentObject private var authManager: AuthManager
    @ObservedObject var social: TrainingSocialStore
    @ObservedObject var store: TrainingStore
    let workout: FriendWorkout
    @State private var comment = ""
    @State private var replyingTo: FriendWorkoutComment?
    @State private var isSending = false
    @State private var submissionError: String?
    @State private var reportTarget: ContentReportTarget?
    @FocusState private var commentFocused: Bool

    private let quickEmojis = ["💪", "🔥", "👏", "🏋️", "👊", "🥵", "🏆"]
    private var detail: FriendWorkoutDetail? { social.detail(for: workout.id) }
    private var current: FriendWorkout { detail?.workout ?? workout }
    private func t(_ key: String, _ arguments: CVarArg...) -> String { language.text(key, arguments) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: HyseSpacing.section) {
                    HStack(spacing: HyseSpacing.medium) {
                        TrainingProfileLink(userID: current.userID, username: current.username, nickname: current.nickname,
                                            avatar: current.avatar, avatarURL: current.avatarURL, social: social, store: store) {
                            HStack(spacing: HyseSpacing.medium) {
                                RemoteProfileAvatarView(userID: current.userID, filename: current.avatar, remoteURL: current.avatarURL, size: 48)
                                VStack(alignment: .leading, spacing: HyseSpacing.xSmall) {
                                    Text(current.username).font(.headline)
                                    if let date = current.date {
                                        Text(date.formatted(.dateTime.weekday(.wide).day().month().year().locale(language.locale)))
                                            .font(.subheadline)
                                            .foregroundStyle(.gray)
                                    }
                                }
                            }
                        }
                        Spacer()
                    }

                    NavigationLink {
                        FriendWorkoutDetailView(social: social, store: store, workout: current)
                    } label: {
                        HStack(spacing: HyseSpacing.medium) {
                            Text(current.name)
                                .font(.title3.bold())
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "chevron.right")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.gray)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    HStack(spacing: HyseSpacing.medium) {
                        Button { Task { await social.toggleLike(workout.id, auth: authManager) } } label: {
                            HStack(spacing: HyseSpacing.xSmall) {
                                if current.likeCount > 0 {
                                    Text("\(current.likeCount)")
                                        .font(.subheadline.weight(.semibold))
                                        .monospacedDigit()
                                }
                                Image(systemName: current.likedByMe ? "hand.thumbsup.fill" : "hand.thumbsup")
                                    .font(.title2)
                            }
                            .foregroundStyle(current.likedByMe ? HyseColor.accent : .secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(t("training.social.likes_count", current.likeCount))
                        if detail?.likes.isEmpty == false {
                            WorkoutLikesSummary(social: social, store: store, workout: current)
                        }
                        if current.likeCount == 0 {
                            Text(t("training.social.likes_count", 0))
                                .font(.subheadline)
                                .foregroundStyle(.gray)
                        }
                    }
                }
                .padding(HyseSpacing.page)

                Rectangle()
                    .fill(Color.white.opacity(0.18))
                    .frame(height: 1)

                if let comments = detail?.comments, !comments.isEmpty {
                    LazyVStack(alignment: .leading, spacing: HyseSpacing.section) {
                        ForEach(orderedWorkoutCommentRows(comments)) { row in
                            let value = row.comment
                            HStack(alignment: .top, spacing: HyseSpacing.medium) {
                                TrainingProfileLink(userID: value.userID, username: value.username, nickname: value.nickname,
                                                    avatar: value.avatar, avatarURL: value.avatarURL, social: social, store: store) {
                                    RemoteProfileAvatarView(userID: value.userID, filename: value.avatar, remoteURL: value.avatarURL, size: 42)
                                }
                                VStack(alignment: .leading, spacing: HyseSpacing.small) {
                                    TrainingProfileLink(userID: value.userID, username: value.username, nickname: value.nickname,
                                                        avatar: value.avatar, avatarURL: value.avatarURL, social: social, store: store) {
                                        Text(value.username).font(.subheadline.bold())
                                    }
                                    if let parentID = value.parentID,
                                       let parent = comments.first(where: { $0.id == parentID }) {
                                        TrainingProfileLink(userID: parent.userID, username: parent.username, nickname: parent.nickname,
                                                            avatar: parent.avatar, avatarURL: parent.avatarURL, social: social, store: store) {
                                            Text("↳ @\(parent.username)")
                                                .font(.caption)
                                                .foregroundStyle(.gray)
                                        }
                                    }
                                    Text(value.body).font(.body)
                                    HStack(spacing: HyseSpacing.medium) {
                                        if let date = value.date {
                                            Text(date.formatted(.relative(presentation: .named)))
                                                .font(.caption)
                                                .foregroundStyle(.gray)
                                        }
                                        Button(t("training.social.reply")) {
                                            replyingTo = value
                                            commentFocused = true
                                        }
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.gray)
                                    }
                                }
                                Spacer(minLength: 0)
                                Menu {
                                    Button { reportTarget = .workoutComment(id: value.id, name: "@\(value.username)") } label: {
                                        Label(t("content_reports.report_comment"), systemImage: "flag")
                                    }
                                    Button { reportTarget = .profile(id: value.userID, name: "@\(value.username)") } label: {
                                        Label(t("content_reports.report_profile"), systemImage: "person.crop.circle.badge.exclamationmark")
                                    }
                                } label: {
                                    Image(systemName: "ellipsis").foregroundStyle(.gray)
                                }
                            }
                            .padding(.leading, CGFloat(min(row.depth, 2)) * 28)
                        }
                    }
                    .padding(HyseSpacing.page)
                } else if detail != nil {
                    VStack(spacing: HyseSpacing.section) {
                        ProfileAvatarView(size: 64, editable: false)
                        Text(t("training.social.be_first_comment"))
                            .font(.subheadline)
                            .foregroundStyle(.gray)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 56)
                    .padding(.horizontal, HyseSpacing.page)
                } else if let error = social.errorMessage {
                    Button(t("content.retry")) { Task { await social.loadDetail(workout, auth: authManager, force: true) } }
                        .frame(maxWidth: .infinity)
                        .padding(.top, HyseSpacing.section)
                        .accessibilityHint(error)
                } else {
                    ProgressView().tint(.white).frame(maxWidth: .infinity).padding(.top, HyseSpacing.section)
                }
            }
        }
        .background(Color.black.ignoresSafeArea())
        .foregroundStyle(.white)
        .safeAreaInset(edge: .bottom, spacing: 0) { composer }
        .simultaneousGesture(
            DragGesture(minimumDistance: 20).onEnded { gesture in
                guard gesture.startLocation.x <= 44,
                      gesture.translation.width > 88,
                      gesture.translation.width > abs(gesture.translation.height) * 1.5 else { return }
                dismiss()
            }
        )
        .navigationTitle(t("training.social.comments"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: {
                    Image(systemName: "arrow.left")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.white)
                }
                .accessibilityLabel(t("training.close"))
            }
        }
        .toolbarBackground(.black, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .preferredColorScheme(.dark)
        .sheet(item: $reportTarget) { target in ContentReportSheet(target: target) }
        .task { await social.loadDetail(workout, auth: authManager, force: true) }
    }

    private var composer: some View {
        VStack(spacing: HyseSpacing.medium) {
            Rectangle().fill(Color.white.opacity(0.18)).frame(height: 1)
            if let submissionError {
                Text(submissionError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, HyseSpacing.page)
            }
            if let replyingTo {
                HStack {
                    Text(t("training.social.replying_to", replyingTo.username))
                        .font(.subheadline)
                        .foregroundStyle(.gray)
                    Spacer()
                    Button { self.replyingTo = nil } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.gray)
                    }
                    .accessibilityLabel(t("common.cancel"))
                }
                .padding(.horizontal, HyseSpacing.page)
            }
            HStack {
                ForEach(quickEmojis, id: \.self) { emoji in
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        comment += emoji
                        commentFocused = true
                    } label: {
                        Text(emoji).font(.title2).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, HyseSpacing.page)
            HStack(spacing: HyseSpacing.medium) {
                TextField(replyingTo == nil ? t("training.social.comment_add_placeholder") : t("training.social.reply_placeholder"), text: $comment, axis: .vertical)
                    .lineLimit(1...3)
                    .focused($commentFocused)
                    .padding(.horizontal, HyseSpacing.large)
                    .padding(.vertical, HyseSpacing.medium)
                    .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                Button { sendComment() } label: {
                    if isSending {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.title3.weight(.semibold))
                    }
                }
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Color.white.opacity(0.12), in: Circle())
                .disabled(comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
            }
            .padding(.horizontal, HyseSpacing.page)
            .padding(.bottom, HyseSpacing.small)
        }
        .background(Color.black)
    }

    private func sendComment() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let value = comment
        let replyToID = replyingTo?.id
        submissionError = nil
        isSending = true
        Task {
            if await social.addComment(value, workoutID: workout.id, replyToID: replyToID, auth: authManager) {
                comment = ""
                replyingTo = nil
            } else {
                submissionError = social.errorMessage
            }
            isSending = false
        }
    }
}

struct WorkoutCommentsSection: View {
    @EnvironmentObject private var language: LanguageStore
    @EnvironmentObject private var authManager: AuthManager
    @ObservedObject var social: TrainingSocialStore
    let store: TrainingStore
    let workoutID: String
    var focusesComment = false
    @State private var comment = ""
    @State private var replyingTo: FriendWorkoutComment?
    @State private var isSending = false
    @State private var submissionError: String?
    @State private var reportTarget: ContentReportTarget?
    @FocusState private var commentFocused: Bool

    private var detail: FriendWorkoutDetail? { social.detail(for: workoutID) }
    private func t(_ key: String, _ arguments: CVarArg...) -> String { language.text(key, arguments) }

    var body: some View {
        VStack(alignment: .leading, spacing: HyseSpacing.medium) {
            Text(t("training.social.comments")).font(.title3.bold())
            if let comments = detail?.comments, !comments.isEmpty {
                ForEach(orderedWorkoutCommentRows(comments)) { row in
                    let value = row.comment
                    HStack(alignment: .top, spacing: HyseSpacing.medium) {
                        TrainingProfileLink(userID: value.userID, username: value.username, nickname: value.nickname,
                                            avatar: value.avatar, avatarURL: value.avatarURL, social: social, store: store) {
                            RemoteProfileAvatarView(userID: value.userID, filename: value.avatar, remoteURL: value.avatarURL, size: 34)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            TrainingProfileLink(userID: value.userID, username: value.username, nickname: value.nickname,
                                                avatar: value.avatar, avatarURL: value.avatarURL, social: social, store: store) {
                                Text("@\(value.username)").font(.subheadline.bold())
                            }
                            if let parentID = value.parentID,
                               let parent = comments.first(where: { $0.id == parentID }) {
                                TrainingProfileLink(userID: parent.userID, username: parent.username, nickname: parent.nickname,
                                                    avatar: parent.avatar, avatarURL: parent.avatarURL, social: social, store: store) {
                                    Text("↳ @\(parent.username)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Text(value.body)
                            HStack(spacing: HyseSpacing.medium) {
                                if let date = value.date { Text(date.formatted(.relative(presentation: .named))).font(.caption2).foregroundStyle(.secondary) }
                                Button(t("training.social.reply")) {
                                    replyingTo = value
                                    commentFocused = true
                                }
                                .font(.caption.weight(.semibold))
                            }
                        }
                        Menu {
                            Button { reportTarget = .workoutComment(id: value.id, name: "@\(value.username)") } label: {
                                Label(t("content_reports.report_comment"), systemImage: "flag")
                            }
                            Button { reportTarget = .profile(id: value.userID, name: "@\(value.username)") } label: {
                                Label(t("content_reports.report_profile"), systemImage: "person.crop.circle.badge.exclamationmark")
                            }
                            if value.avatar?.isEmpty == false {
                                Button { reportTarget = .avatar(id: value.userID, name: "@\(value.username)") } label: {
                                    Label(t("content_reports.report_avatar"), systemImage: "photo.badge.exclamationmark")
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle").foregroundStyle(.secondary)
                        }
                    }
                    .padding(.leading, CGFloat(min(row.depth, 2)) * 24)
                }
            } else if detail != nil {
                Text(t("training.social.no_comments")).foregroundStyle(.secondary)
            }

            if let replyingTo {
                HStack {
                    Text(t("training.social.replying_to", replyingTo.username)).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button { self.replyingTo = nil } label: { Image(systemName: "xmark.circle.fill") }
                        .accessibilityLabel(t("common.cancel"))
                }
            }
            if let submissionError {
                Text(submissionError).font(.caption).foregroundStyle(.red)
            }
            HStack(spacing: HyseSpacing.small) {
                TextField(replyingTo == nil ? t("training.social.comment_placeholder") : t("training.social.reply_placeholder"), text: $comment, axis: .vertical)
                    .textFieldStyle(.plain)
                    .focused($commentFocused)
                    .padding(.horizontal, HyseSpacing.medium)
                    .padding(.vertical, HyseSpacing.small)
                    .background(HyseColor.surface, in: RoundedRectangle(cornerRadius: HyseRadius.control, style: .continuous))
                Button { sendComment() } label: {
                    if isSending { ProgressView() } else { Image(systemName: "arrow.up.circle.fill").font(.title2) }
                }
                .disabled(comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
            }
        }
        .sheet(item: $reportTarget) { target in
            ContentReportSheet(target: target)
        }
        .task {
            if focusesComment { try? await Task.sleep(for: .milliseconds(250)); commentFocused = true }
        }
    }

    private func sendComment() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let value = comment
        let replyToID = replyingTo?.id
        submissionError = nil
        isSending = true
        Task {
            if await social.addComment(value, workoutID: workoutID, replyToID: replyToID, auth: authManager) {
                comment = ""
                replyingTo = nil
            } else {
                submissionError = social.errorMessage
            }
            isSending = false
        }
    }
}

struct FriendWorkoutDetailView: View {
    @EnvironmentObject private var language: LanguageStore
    @EnvironmentObject private var authManager: AuthManager
    @AppStorage("countUnilateralSetsAsHalf_v1") private var halveUnilateral = false
    @ObservedObject var social: TrainingSocialStore
    @ObservedObject var store: TrainingStore
    let workout: FriendWorkout
    var focusesComment = false
    @State private var isMuscleSplitExpanded = false
    @State private var showingCopiedWorkout = false
    @State private var showingShareComposer = false
    @State private var reportTarget: ContentReportTarget?
    @AppStorage("trainingDistanceUnit_v1") private var trainingDistanceUnitRaw = TrainingDistanceUnit.kilometers.rawValue

    private var detail: FriendWorkoutDetail? { social.detail(for: workout.id) }
    private var current: FriendWorkout { detail?.workout ?? workout }
    private var localWorkout: WorkoutLog? {
        store.completedWorkouts.first {
            $0.remoteID == current.id
                || $0.id.uuidString.caseInsensitiveCompare(current.clientID ?? current.id) == .orderedSame
        }
    }
    private var distanceUnit: TrainingDistanceUnit { TrainingDistanceUnit(rawValue: trainingDistanceUnitRaw) ?? .kilometers }
    private func t(_ key: String, _ arguments: CVarArg...) -> String { language.text(key, arguments) }

    var body: some View {
        ZStack {
            HyseBackdrop()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: HyseSpacing.large) {
                    VStack(alignment: .leading, spacing: HyseSpacing.medium) {
                        HStack(spacing: HyseSpacing.medium) {
                            TrainingProfileLink(userID: current.userID, username: current.username, nickname: current.nickname,
                                                avatar: current.avatar, avatarURL: current.avatarURL, social: social, store: store) {
                                HStack(spacing: HyseSpacing.medium) {
                                    RemoteProfileAvatarView(userID: current.userID, filename: current.avatar, remoteURL: current.avatarURL, size: 52)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("@\(current.username)").font(.headline)
                                        if let date = current.date {
                                            Text(date.formatted(.dateTime.weekday(.wide).day().month().year().hour().minute().locale(language.locale)))
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                        HStack(alignment: .top, spacing: HyseSpacing.medium) {
                            VStack(alignment: .leading, spacing: HyseSpacing.small) {
                                Text(current.name)
                                    .font(.title2.bold())
                                    .fixedSize(horizontal: false, vertical: true)
                                if let gymName = localWorkout?.gymName ?? detail?.snapshot?.gymName,
                                   !gymName.isEmpty {
                                    HStack(alignment: .top, spacing: HyseSpacing.small) {
                                        Image(systemName: "mappin.and.ellipse")
                                            .foregroundStyle(HyseColor.accent)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(gymName)
                                                .font(.subheadline.weight(.semibold))
                                            if let address = localWorkout?.gymAddress ?? detail?.snapshot?.gymAddress,
                                               !address.isEmpty {
                                                Text(address)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                    .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            if localWorkout?.mediaLocalFilename != nil || current.mediaURL?.isEmpty == false {
                                WorkoutMediaView(
                                    localFilename: localWorkout?.mediaLocalFilename,
                                    remoteURL: current.mediaURL,
                                    compact: true,
                                    compactSize: 88
                                )
                            }
                        }
                        WorkoutCommentsSection(social: social, store: store, workoutID: workout.id, focusesComment: focusesComment)
                        HStack(spacing: 0) {
                            metric(t("training.duration"), activeWorkoutDurationText(current.duration))
                            metric(t("training.total_volume"), volume(current.totalVolume))
                            metric(t("training.completed_sets"), TrainingSetStatistics.formatted(detail?.snapshot.map { TrainingSetStatistics.count($0, halveUnilateral: halveUnilateral) } ?? 0, locale: language.locale))
                        }
                        if !(localWorkout?.notes ?? current.notes).isEmpty {
                            Text(localWorkout?.notes ?? current.notes).foregroundStyle(.secondary)
                        }
                    }

                    HStack(spacing: HyseSpacing.large) {
                        Button { Task { await social.toggleLike(workout.id, auth: authManager) } } label: {
                            Label("\(current.likeCount)", systemImage: current.likedByMe ? "hand.thumbsup.fill" : "hand.thumbsup")
                                .foregroundStyle(current.likedByMe ? HyseColor.accent : .secondary)
                        }
                        Button { showingShareComposer = true } label: {
                            Label(t("training.social.share"), systemImage: "square.and.arrow.up")
                        }
                        .disabled(shareWorkout == nil)
                        Spacer()
                    }
                    .buttonStyle(.plain)
                    WorkoutLikesSummary(social: social, store: store, workout: current)
                    Divider()

                    if !muscleSplit.isEmpty {
                        VStack(alignment: .leading, spacing: HyseSpacing.large) {
                            Text(t("training.feed.muscle_split"))
                                .font(.title3)
                                .foregroundStyle(.secondary)
                            ForEach(Array(muscleSplit.prefix(isMuscleSplitExpanded ? muscleSplit.count : 2)), id: \.muscle) { entry in
                                VStack(alignment: .leading, spacing: HyseSpacing.small) {
                                    Text(t("training.muscle.\(entry.muscle)"))
                                        .font(.headline)
                                    HStack(spacing: HyseSpacing.small) {
                                        ProgressView(value: entry.fraction)
                                            .tint(HyseColor.accent)
                                            .scaleEffect(x: 1, y: 2.2, anchor: .center)
                                        Text(entry.fraction.formatted(.percent.precision(.fractionLength(0))))
                                            .font(.headline)
                                            .foregroundStyle(.secondary)
                                            .monospacedDigit()
                                            .frame(width: 48, alignment: .leading)
                                    }
                                }
                            }
                            if muscleSplit.count > 2 {
                                Button {
                                    withAnimation(HyseMotion.standard) { isMuscleSplitExpanded.toggle() }
                                } label: {
                                    Label(
                                        isMuscleSplitExpanded
                                            ? t("training.feed.fewer_muscles")
                                            : t("training.feed.more_muscles", muscleSplit.count - 2),
                                        systemImage: isMuscleSplitExpanded ? "chevron.up" : "chevron.down"
                                    )
                                    .font(.subheadline.weight(.semibold))
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(HyseColor.accent)
                            }
                        }
                    }

                    if let snapshot = detail?.snapshot {
                        HStack {
                            Text(t("training.feed.workout"))
                                .font(.title3)
                                .foregroundStyle(.secondary)
                            Spacer()
                            if current.userID == authManager.accountID {
                                Text(t("training.feed.your_workout"))
                                    .font(.subheadline)
                                    .foregroundStyle(HyseColor.accent)
                            }
                        }
                        ForEach(snapshot.exercises) { exercise in
                            workoutExerciseSection(exercise)
                        }
                    } else {
                        HStack { Spacer(); ProgressView(); Spacer() }.padding()
                    }
                }
                .padding(HyseSpacing.page)
            }
        }
        .navigationTitle(t("training.social.workout_details"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showingShareComposer = true } label: {
                        Label(t("training.feed.share"), systemImage: "square.and.arrow.up")
                    }
                    .disabled(shareWorkout == nil)
                    if let ownerID = current.userID, ownerID != authManager.accountID {
                        Button { reportTarget = .workout(id: current.id, name: current.name) } label: {
                            Label(t("content_reports.report_workout"), systemImage: "flag")
                        }
                        Button { reportTarget = .profile(id: ownerID, name: "@\(current.username)") } label: {
                            Label(t("content_reports.report_profile"), systemImage: "person.crop.circle.badge.exclamationmark")
                        }
                        if current.avatar?.isEmpty == false {
                            Button { reportTarget = .avatar(id: ownerID, name: "@\(current.username)") } label: {
                                Label(t("content_reports.report_avatar"), systemImage: "photo.badge.exclamationmark")
                            }
                        }
                    }
                    if let snapshot = detail?.snapshot {
                        Button { store.createRoutine(from: snapshot) } label: {
                            Label(t("training.feed.save_as_routine"), systemImage: "square.and.arrow.down")
                        }
                        Button {
                            guard store.activeWorkout == nil else { return }
                            store.repeatWorkout(snapshot)
                            showingCopiedWorkout = true
                        } label: {
                            Label(t("training.feed.copy"), systemImage: "square.on.square")
                        }
                        .disabled(store.activeWorkout != nil)
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 40, height: 40)
                }
            }
        }
        .sheet(item: $reportTarget) { target in
            ContentReportSheet(target: target)
        }
        .sheet(isPresented: $showingShareComposer) {
            if let shareWorkout {
                WorkoutShareComposer(
                    workout: shareWorkout,
                    muscleCounts: WorkoutShareMuscles.counts(for: shareWorkout),
                    store: store,
                    shareURLOverride: WorkoutShareLink.url(workoutID: current.id, isGerman: language.isGerman),
                    ownerUsername: current.username
                )
                .environmentObject(language)
            }
        }
        .fullScreenCover(isPresented: $showingCopiedWorkout) {
            ActiveWorkoutView(store: store, animateToLatestCompletedExercise: false)
        }
        .task {
            await social.loadDetail(workout, auth: authManager)
        }
    }

    private var shareWorkout: WorkoutLog? { detail?.snapshot ?? localWorkout }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline).monospacedDigit().lineLimit(1).minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var muscleSplit: [(muscle: String, fraction: Double)] {
        guard let snapshot = detail?.snapshot else { return [] }
        var counts: [String: Int] = [:]
        for exercise in snapshot.exercises {
            let setCount = exercise.completedWorkingSetCount
            guard setCount > 0 else { continue }
            for muscle in exercise.primaryMusclesSnapshot {
                counts[muscle, default: 0] += setCount
            }
        }
        let total = max(1, counts.values.reduce(0, +))
        return counts.map { ($0.key, Double($0.value) / Double(total)) }
            .sorted { left, right in
                if left.fraction != right.fraction { return left.fraction > right.fraction }
                let leftName = t("training.muscle.\(left.muscle)")
                let rightName = t("training.muscle.\(right.muscle)")
                let order = leftName.compare(rightName, options: [.caseInsensitive, .diacriticInsensitive], locale: language.locale)
                return order == .orderedSame ? left.muscle < right.muscle : order == .orderedAscending
            }
    }

    private func workoutExerciseSection(_ exercise: WorkoutExerciseLog) -> some View {
        VStack(alignment: .leading, spacing: HyseSpacing.medium) {
            HStack(spacing: HyseSpacing.medium) {
                ExerciseMovementVisual(exercise: exerciseForVisual(exercise), height: 52)
                Text(exerciseName(exercise))
                    .font(.title3.bold())
                    .foregroundStyle(HyseColor.accent)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Text(t("training.feed.set"))
                    .frame(width: 44, alignment: .leading)
                Text(t("training.feed.result"))
                Spacer()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            ForEach(Array(exercise.sets.filter(\.completed).enumerated()), id: \.element.id) { index, set in
                HStack {
                    Text("\(index + 1)")
                        .frame(width: 44, alignment: .leading)
                    Text(setDescription(set, type: exercise.exerciseTypeSnapshot))
                        .monospacedDigit()
                    Spacer()
                }
                .font(.body)
            }
        }
        .padding(.vertical, HyseSpacing.small)
    }

    private func exerciseName(_ exercise: WorkoutExerciseLog) -> String {
        language.isGerman && !exercise.exerciseGermanNameSnapshot.isEmpty
            ? exercise.exerciseGermanNameSnapshot
            : exercise.exerciseNameSnapshot
    }

    private func exerciseForVisual(_ log: WorkoutExerciseLog) -> TrainingExercise {
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

    private func duration(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        return minutes >= 60 ? "\(minutes / 60) h \(minutes % 60) min" : "\(minutes) min"
    }

    private func volume(_ kilograms: Double) -> String {
        kilograms >= 1000 ? "\((kilograms / 1000).formatted(.number.precision(.fractionLength(1)))) t" : "\(kilograms.formatted(.number.precision(.fractionLength(0)))) kg"
    }

    private func setDescription(_ set: TrainingSetLog, type: TrainingExerciseType) -> String {
        switch type {
        case .weightReps: return "\(set.weightKilograms.formatted(.number.precision(.fractionLength(0...1)))) kg × \(set.reps)"
        case .bodyweight, .repsOnly: return "\(set.reps) \(t("training.reps"))"
        case .duration: return duration(set.durationSeconds)
        case .distanceDuration: return "\(distanceUnit.display(set.distanceMeters).formatted(.number.precision(.fractionLength(0...2)))) \(distanceUnit.rawValue) · \(duration(set.durationSeconds)) · \(paceText(set))"
        }
    }

    private func paceText(_ set: TrainingSetLog) -> String {
        guard let seconds = distanceUnit.paceSeconds(durationSeconds: set.durationSeconds, distanceMeters: set.distanceMeters) else { return "–" }
        return "\(Int(seconds) / 60):\(String(format: "%02d", Int(seconds) % 60)) /\(distanceUnit.rawValue)"
    }
}

struct TrainingPublicProfileView: View {
    @EnvironmentObject private var language: LanguageStore
    @EnvironmentObject private var auth: AuthManager
    let initialUser: TrainingSocialUser
    @ObservedObject var social: TrainingSocialStore
    @ObservedObject var store: TrainingStore
    @State private var profile: TrainingPublicProfile?
    @State private var relationshipState: String?
    @State private var isLoading = false
    @State private var isRequestingFriend = false
    @State private var errorMessage: String?
    @State private var reportTarget: ContentReportTarget?
    @State private var selectedHoursWeek: Date?

    private func t(_ key: String, _ arguments: CVarArg...) -> String { language.text(key, arguments) }
    private var user: TrainingSocialUser { profile?.user ?? initialUser }
    private var state: String { relationshipState ?? user.state ?? "none" }

    var body: some View {
        ZStack {
            HyseBackdrop()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: HyseSpacing.large) {
                    profileHeader

                    if let errorMessage {
                        HyseStatusBanner(title: t("training.social.error_title"), message: errorMessage, style: .warning)
                    }

                    if isLoading && profile == nil {
                        ProgressView().frame(maxWidth: .infinity).padding(.vertical, HyseSpacing.section)
                    } else if profile != nil {
                        if profile?.workoutCount != nil {
                            if !(profile?.weeklyHours.isEmpty ?? true) { weeklyHoursChart }
                            publicRoutinesSection
                        }
                        recentWorkoutsSection
                    }
                }
                .padding(HyseSpacing.page)
                .padding(.bottom, HyseSpacing.section)
            }
            .refreshable { await loadProfile(force: true) }
        }
        .navigationTitle(user.username.isEmpty ? t("training.social.profile") : user.username)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !user.username.isEmpty {
                ShareLink(item: "@\(user.username)") {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel(t("training.social.share"))
            }
            if user.id != auth.accountID {
                Menu {
                    Button { reportTarget = .profile(id: user.id, name: "@\(user.username)") } label: {
                        Label(t("content_reports.report_profile"), systemImage: "flag")
                    }
                    if user.avatar?.isEmpty == false {
                        Button { reportTarget = .avatar(id: user.id, name: "@\(user.username)") } label: {
                            Label(t("content_reports.report_avatar"), systemImage: "photo.badge.exclamationmark")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
            }
        }
        .sheet(item: $reportTarget) { target in
            ContentReportSheet(target: target)
        }
        .task { await loadProfile(force: false) }
    }

    private var userWorkouts: [FriendWorkout] { profile?.workouts ?? [] }

    private var profileHeader: some View {
        VStack(alignment: .leading, spacing: HyseSpacing.medium) {
            HStack(alignment: .center, spacing: HyseSpacing.medium) {
                RemoteProfileAvatarView(userID: user.id, filename: user.avatar, remoteURL: user.avatarURL, size: 88)
                VStack(alignment: .leading, spacing: HyseSpacing.small) {
                    Text(user.displayName.isEmpty ? t("training.social.no_username") : user.displayName)
                        .font(.title2.bold())
                        .lineLimit(2)
                    HStack(alignment: .top, spacing: HyseSpacing.medium) {
                        profileStat("Workouts", profile?.workoutCount.map(String.init) ?? "–")
                        profileStat(t("training.social.friends"), profile?.friendCount.map(String.init) ?? "–")
                        profileStat(t("training.routines"), profile?.routineCount.map(String.init) ?? "–")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            profileRelationship
            if let bio = user.bio, !bio.isEmpty {
                Text(bio)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let website = user.website, let url = URL(string: website), url.scheme == "https" {
                Link(website.replacingOccurrences(of: "https://", with: ""), destination: url)
                    .font(.subheadline)
                    .foregroundStyle(HyseColor.accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func profileStat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.75)
            Text(value).font(.headline).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var weeklyHoursChart: some View {
        let weeks = profile?.weeklyHours ?? []
        let selectedWeek = weeks.first { $0.date == selectedHoursWeek }
        let currentHours = selectedWeek?.hours ?? weeks.last?.hours ?? 0
        let selectedWeekLabel = selectedWeek?.date?.formatted(.dateTime.day().month(.abbreviated).locale(language.locale))
        return VStack(alignment: .leading, spacing: HyseSpacing.medium) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(currentHours.formatted(.number.precision(.fractionLength(0...1)).grouping(.never).locale(language.locale)))
                    .font(.title2.bold())
                Text(selectedWeekLabel.map { language.isGerman ? "Stunden ab \($0)" : "hours from \($0)" }
                     ?? (language.isGerman ? "Stunden diese Woche" : "hours this week"))
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            Chart {
                ForEach(weeks) { week in
                    if let date = week.date {
                        BarMark(x: .value("Week", date, unit: .weekOfYear), y: .value("Hours", week.hours))
                            .foregroundStyle(selectedHoursWeek == nil || selectedHoursWeek == date ? HyseColor.accent : HyseColor.accent.opacity(0.35))
                            .cornerRadius(2)
                            .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                                if selectedHoursWeek == date {
                                    Text(week.hours.formatted(.number.precision(.fractionLength(0...1)).grouping(.never).locale(language.locale)))
                                        .font(.caption.weight(.semibold))
                                        .monospacedDigit()
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 4)
                                        .background(HyseColor.surface, in: RoundedRectangle(cornerRadius: HyseRadius.small))
                                }
                            }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .weekOfYear, count: 3)) { _ in
                    AxisGridLine().foregroundStyle(.clear)
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                }
            }
            .chartYAxis { AxisMarks(position: .leading) }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0).onChanged { gesture in
                            selectedHoursWeek = ChartBarSelection.date(
                                at: gesture.location, proxy: proxy, geometry: geometry,
                                bars: weeks.compactMap { week in week.date.map { ($0, week.hours) } },
                                unit: .weekOfYear
                            )
                        })
                }
            }
            .frame(height: 160)
            Text(language.isGerman ? "Öffentlich geteilte Workouts" : "Publicly shared workouts")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var publicRoutinesSection: some View {
        VStack(alignment: .leading, spacing: HyseSpacing.medium) {
            Text(t("training.routines")).font(.title3).foregroundStyle(.secondary)
            if let routines = profile?.routines, !routines.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: HyseSpacing.medium) {
                        ForEach(routines) { routine in
                            Text(routine.name)
                                .font(.headline)
                                .frame(width: 150, height: 104, alignment: .topLeading)
                                .padding(HyseSpacing.medium)
                                .background(HyseColor.surface, in: RoundedRectangle(cornerRadius: HyseRadius.card))
                        }
                    }
                }
            } else {
                Text(language.isGerman ? "Keine öffentlichen Routinen" : "No public routines")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var recentWorkoutsSection: some View {
        VStack(alignment: .leading, spacing: HyseSpacing.medium) {
            Text(language.isGerman ? "Letzte Workouts" : "Recent workouts")
                .font(.title3)
                .foregroundStyle(.secondary)
            if userWorkouts.isEmpty {
                HyseEmptyState(icon: "figure.strengthtraining.traditional", title: t("training.social.profile_no_workouts"), message: t("training.social.profile_no_workouts_message"))
            } else {
                ForEach(userWorkouts) { workout in
                    NavigationLink {
                        FriendWorkoutDetailView(social: social, store: store, workout: workout)
                    } label: {
                        publicWorkoutRow(workout)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(HyseSpacing.medium)
                            .background(HyseColor.surface, in: RoundedRectangle(cornerRadius: HyseRadius.card))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder private var profileRelationship: some View {
        if user.id == auth.accountID || state == "self" {
            Label(t("training.social.you"), systemImage: "person.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            switch state {
            case "friends":
                Label(t("training.social.friends_state"), systemImage: "person.2.fill")
                    .font(.caption)
                    .foregroundStyle(HyseColor.accent)
            case "requested":
                Label(t("training.social.requested"), systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case "incoming":
                Label(t("training.social.incoming"), systemImage: "person.badge.plus")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            default:
                Button {
                    sendFriendRequest()
                } label: {
                    if isRequestingFriend {
                        ProgressView().controlSize(.small)
                    } else {
                        Label(t("training.social.add"), systemImage: "person.badge.plus")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(HyseColor.accent)
            }
        }
    }

    private func publicWorkoutRow(_ workout: FriendWorkout) -> some View {
        VStack(alignment: .leading, spacing: HyseSpacing.small) {
            HStack(spacing: HyseSpacing.small) {
                RemoteProfileAvatarView(userID: user.id, filename: user.avatar, remoteURL: user.avatarURL, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(user.username).font(.subheadline.weight(.semibold))
                    if let date = workout.date {
                        Text(date.formatted(.dateTime.weekday(.wide).day().month().year().locale(language.locale)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Text(workout.name)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(2)
            if workout.mediaURL?.isEmpty == false {
                WorkoutMediaView(remoteURL: workout.mediaURL, compact: true, compactSize: 80)
            }
            HStack(spacing: HyseSpacing.medium) {
                Label(formatDuration(workout.duration), systemImage: "clock")
                Label(formattedVolume(workout.totalVolume), systemImage: "scalemass")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if !workout.exercisePreview.isEmpty {
                Divider()
                ForEach(workout.exercisePreview.indices, id: \.self) { index in
                    let exercise = workout.exercisePreview[index]
                    let name = language.isGerman && !exercise.germanName.isEmpty ? exercise.germanName : exercise.name
                    if !name.isEmpty {
                        Text("\(exercise.setCount) \(language.isGerman ? (exercise.setCount == 1 ? "Satz" : "Sätze") : (exercise.setCount == 1 ? "set" : "sets")) · \(name)")
                            .font(.subheadline)
                            .lineLimit(1)
                    }
                }
            }
            if !workout.notes.isEmpty {
                Text(workout.notes)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func loadProfile(force: Bool) async {
        guard auth.isLoggedIn, !auth.token.isEmpty else { return }
        if !force, profile != nil { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let value = try await TrainingSocialService.shared.publicProfile(initialUser.id, token: auth.token)
            profile = value
            selectedHoursWeek = nil
            relationshipState = value.user.state
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription == "training.social.error"
                ? t("training.social.error")
                : error.localizedDescription
        }
    }

    private func sendFriendRequest() {
        guard !isRequestingFriend, user.id != auth.accountID else { return }
        isRequestingFriend = true
        Task {
            do {
                try await TrainingSocialService.shared.requestFriend(user.id, token: auth.token)
                await MainActor.run {
                    relationshipState = "requested"
                    errorMessage = nil
                    isRequestingFriend = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription == "training.social.error"
                        ? t("training.social.error")
                        : error.localizedDescription
                    isRequestingFriend = false
                }
            }
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        return "\(total / 3600):\(String(format: "%02d", (total % 3600) / 60))"
    }

    private func formattedVolume(_ kilograms: Double) -> String {
        kilograms >= 1000
            ? "\((kilograms / 1000).formatted(.number.precision(.fractionLength(1)))) t"
            : "\(kilograms.formatted(.number.precision(.fractionLength(0)))) kg"
    }
}

enum TrainingConnectionListKind {
    case friends
    case followers

    var titleKey: String {
        switch self {
        case .friends: "training.social.friends"
        case .followers: "training.social.followers"
        }
    }

    var emptyKey: String {
        switch self {
        case .friends: "training.social.no_friends"
        case .followers: "training.social.no_followers"
        }
    }

    var icon: String {
        switch self {
        case .friends: "person.2.fill"
        case .followers: "person.crop.circle.badge.checkmark"
        }
    }
}

struct TrainingConnectionsListView: View {
    @EnvironmentObject private var language: LanguageStore
    @EnvironmentObject private var authManager: AuthManager
    let kind: TrainingConnectionListKind
    @ObservedObject var social: TrainingSocialStore
    @ObservedObject var store: TrainingStore

    private func t(_ key: String) -> String { language.text(key) }

    var body: some View {
        ZStack {
            HyseBackdrop()
            if social.friends.isEmpty {
                HyseEmptyState(
                    icon: kind.icon,
                    title: t(kind.titleKey),
                    message: t(kind.emptyKey)
                )
                .padding(HyseSpacing.page)
            } else {
                ScrollView {
                    LazyVStack(spacing: HyseSpacing.medium) {
                        ForEach(social.friends) { connection in
                            NavigationLink {
                                TrainingPublicProfileView(initialUser: connection.profileUser, social: social, store: store)
                            } label: {
                                HyseCard {
                                    HStack(spacing: HyseSpacing.medium) {
                                        RemoteProfileAvatarView(
                                            userID: connection.userID,
                                            filename: connection.avatar,
                                            remoteURL: connection.avatarURL,
                                            size: 48
                                        )
                                        VStack(alignment: .leading, spacing: HyseSpacing.xSmall) {
                                            Text(connection.displayName)
                                                .font(.headline)
                                                .foregroundStyle(.primary)
                                            Label(t(kind == .friends ? "training.social.friends_state" : "training.social.follower_state"), systemImage: kind.icon)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer(minLength: 0)
                                        Image(systemName: "chevron.right")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, HyseSpacing.page)
                    .padding(.vertical, HyseSpacing.medium)
                }
                .refreshable { await social.load(auth: authManager, force: true) }
            }
        }
        .navigationTitle(t(kind.titleKey))
        .navigationBarTitleDisplayMode(.inline)
        .task { await social.load(auth: authManager) }
    }
}

struct TrainingFriendsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var language: LanguageStore
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var settings: UserSettingsStore
    @ObservedObject var social: TrainingSocialStore
    @ObservedObject var store: TrainingStore
    @State private var query = ""
    @State private var friendPendingRemoval: TrainingFriendConnection?
    private func t(_ key: String, _ arguments: CVarArg...) -> String { language.text(key, arguments) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField(t("training.social.search_placeholder"), text: $query)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.search)
                            .onSubmit { search() }
                        Button { search() } label: {
                            if social.isSearching {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "magnifyingglass")
                            }
                        }
                            .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).count < 2)
                    }
                } footer: { Text(t("training.social.search_explanation")) }

                if !social.searchResults.isEmpty {
                    Section(t("training.social.search_results")) {
                        ForEach(social.searchResults) { user in
                            HStack {
                                TrainingProfileLink(userID: user.id, username: user.username, nickname: user.nickname,
                                                    avatar: user.avatar, avatarURL: user.avatarURL, social: social, store: store) {
                                    HStack {
                                        RemoteProfileAvatarView(userID: user.id, filename: user.avatar, remoteURL: user.avatarURL, size: 32)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(user.displayName)
                                            Text("@\(user.username)").font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                Spacer()
                                searchAction(user)
                            }
                        }
                    }
                }

                if !social.requests.isEmpty {
                    Section(t("training.social.requests")) {
                        ForEach(social.requests) { request in
                            HStack {
                                TrainingProfileLink(userID: request.userID, username: request.username, nickname: request.nickname,
                                                    avatar: request.avatar, avatarURL: request.avatarURL, social: social, store: store) {
                                    HStack {
                                        RemoteProfileAvatarView(userID: request.userID, filename: request.avatar, remoteURL: request.avatarURL, size: 32)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(request.displayName)
                                            Text("@\(request.username)").font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                Spacer()
                                Button(t("training.social.accept")) { acceptFriend(request) }.buttonStyle(.borderedProminent)
                                Button { Task { await social.remove(request, auth: authManager) } } label: { Image(systemName: "xmark") }.buttonStyle(.bordered)
                            }
                        }
                    }
                }

                Section(t("training.social.friends")) {
                    if social.friends.isEmpty {
                        Text(t("training.social.no_friends")).foregroundStyle(.secondary)
                    }
                    ForEach(social.friends) { friend in
                        HStack {
                            NavigationLink {
                                TrainingPublicProfileView(initialUser: friend.profileUser, social: social, store: store)
                            } label: {
                                HStack(spacing: HyseSpacing.medium) {
                                    RemoteProfileAvatarView(userID: friend.userID, filename: friend.avatar, remoteURL: friend.avatarURL, size: 36)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(friend.displayName).foregroundStyle(.primary)
                                        Text("@\(friend.username)").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            Spacer()
                            Button(role: .destructive) { friendPendingRemoval = friend } label: {
                                Image(systemName: "person.fill.xmark")
                            }
                            .accessibilityLabel(t("training.social.remove_friend"))
                        }
                    }
                }

                if let error = social.errorMessage {
                    Section { Text(error).font(.caption).foregroundStyle(HyseColor.warning) }
                }
            }
            .hyseForm()
            .navigationTitle(t("training.social.manage_friends"))
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(t("add_entry.done")) { dismiss() } } }
            .task { await social.load(auth: authManager) }
            .task(id: query) {
                let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
                social.prepareLiveSearch(value)
                if value.count >= 2 {
                    do { try await Task.sleep(for: .milliseconds(260)) }
                    catch { return }
                }
                guard !Task.isCancelled else { return }
                await social.search(value, auth: authManager)
            }
            .alert(
                t("training.social.remove_friend_title"),
                isPresented: Binding(
                    get: { friendPendingRemoval != nil },
                    set: { if !$0 { friendPendingRemoval = nil } }
                )
            ) {
                Button(t("app_tabs.cancel"), role: .cancel) { friendPendingRemoval = nil }
                Button(t("training.social.remove_friend"), role: .destructive) { confirmFriendRemoval() }
            } message: {
                Text(t("training.social.remove_friend_message", friendPendingRemoval?.username ?? ""))
            }
        }
    }

    @ViewBuilder private func searchAction(_ user: TrainingSocialUser) -> some View {
        switch user.state ?? "none" {
        case "friends": Text(t("training.social.friends_state")).font(.caption).foregroundStyle(.secondary)
        case "requested": Text(t("training.social.requested")).font(.caption).foregroundStyle(.secondary)
        case "incoming": Text(t("training.social.incoming")).font(.caption).foregroundStyle(.secondary)
        default:
            Button(t("training.social.add")) { Task { await social.requestFriend(user, auth: authManager) } }.buttonStyle(.borderedProminent)
        }
    }

    private func search() { Task { await social.search(query, auth: authManager) } }

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

    private func confirmFriendRemoval() {
        guard let friend = friendPendingRemoval else { return }
        friendPendingRemoval = nil
        Task { await social.remove(friend, auth: authManager) }
    }
}

struct TrainingProfileEditView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var language: LanguageStore
    @EnvironmentObject private var authManager: AuthManager
    @ObservedObject var social: TrainingSocialStore

    @State private var username = ""
    @State private var nickname = ""
    @State private var bio = ""
    @State private var website = ""
    @State private var isSaving = false
    @State private var saveErrorMessage: String?

    private func t(_ key: String, _ arguments: CVarArg...) -> String { language.text(key, arguments) }
    private var normalized: String { username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    private var isValid: Bool { normalized.range(of: "^[a-z0-9_]{3,24}$", options: .regularExpression) != nil }
    private var normalizedNickname: String { String(nickname.trimmingCharacters(in: .whitespacesAndNewlines).prefix(32)) }
    private var normalizedBio: String { bio.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var normalizedWebsite: String {
        let value = website.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty || value.hasPrefix("https://") ? value : "https://\(value)"
    }
    private var isValidWebsite: Bool {
        normalizedWebsite.isEmpty || (normalizedWebsite.count <= 200 && URL(string: normalizedWebsite)?.host != nil)
    }
    private var hasChanges: Bool {
        normalized != social.username || normalizedNickname != social.nickname
            || normalizedBio != social.bio || normalizedWebsite != social.website || social.needsBioPublication
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: HyseSpacing.xLarge) {
                    VStack(spacing: HyseSpacing.medium) {
                        ProfileAvatarView(size: 124, editable: true)
                        Text(t("training.social.change_picture"))
                            .font(.headline)
                            .foregroundStyle(HyseColor.accent)
                    }
                    .frame(maxWidth: .infinity)

                    VStack(alignment: .leading, spacing: HyseSpacing.small) {
                        Text(t("training.social.public_profile"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        HStack(spacing: HyseSpacing.medium) {
                            Text(t("training.social.nickname"))
                                .font(.body)
                            TextField(t("training.social.nickname_placeholder"), text: $nickname)
                                .multilineTextAlignment(.trailing)
                                .textInputAutocapitalization(.words)
                                .disabled(isSaving)
                        }
                        .padding(.horizontal, HyseSpacing.medium)
                        .padding(.vertical, HyseSpacing.large)
                        .background(HyseColor.surface, in: RoundedRectangle(cornerRadius: HyseRadius.control, style: .continuous))

                        Text(t("training.social.nickname_rules"))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack(spacing: HyseSpacing.medium) {
                            Text(t("training.social.username"))
                                .font(.body)
                            TextField(t("training.social.username"), text: $username)
                                .multilineTextAlignment(.trailing)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .disabled(isSaving)
                        }
                        .padding(.horizontal, HyseSpacing.medium)
                        .padding(.vertical, HyseSpacing.large)
                        .background(HyseColor.surface, in: RoundedRectangle(cornerRadius: HyseRadius.control, style: .continuous))

                        Text(t("training.social.username_rules"))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: HyseSpacing.small) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(t("training.social.bio"))
                                    .font(.body)

                                Spacer()

                                Text("\(bio.count)/160")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(bio.count > 160 ? HyseColor.warning : .secondary)
                            }

                            ZStack(alignment: .topLeading) {
                                if bio.isEmpty {
                                    Text(t("training.social.bio_placeholder"))
                                        .font(.body)
                                        .foregroundStyle(.tertiary)
                                        .padding(.horizontal, HyseSpacing.medium)
                                        .padding(.vertical, HyseSpacing.large)
                                        .allowsHitTesting(false)
                                }

                                TextEditor(text: $bio)
                                    .font(.body)
                                    .scrollContentBackground(.hidden)
                                    .padding(.horizontal, HyseSpacing.small)
                                    .padding(.vertical, HyseSpacing.xSmall)
                                    .disabled(isSaving)
                            }
                            .frame(height: 116)
                            .background(HyseColor.surface, in: RoundedRectangle(cornerRadius: HyseRadius.control, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: HyseRadius.control, style: .continuous)
                                    .stroke(HyseColor.border, lineWidth: 0.5)
                            }
                        }

                        Text(t("training.social.bio_rules"))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack(spacing: HyseSpacing.medium) {
                            Text("Website")
                            TextField("example.com", text: $website)
                                .keyboardType(.URL)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .multilineTextAlignment(.trailing)
                                .disabled(isSaving)
                        }
                        .padding(.horizontal, HyseSpacing.medium)
                        .padding(.vertical, HyseSpacing.large)
                        .background(HyseColor.surface, in: RoundedRectangle(cornerRadius: HyseRadius.control, style: .continuous))
                    }

                    if let error = saveErrorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(HyseColor.warning)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, HyseSpacing.page)
                .padding(.top, HyseSpacing.large)
                .padding(.bottom, HyseSpacing.section)
            }
            .background(HyseColor.background.ignoresSafeArea())
            .navigationTitle(t("training.social.edit_profile"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                    }
                    .accessibilityLabel(t("app_tabs.cancel"))
                    .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { save() } label: {
                        if isSaving { ProgressView() }
                        else { Text(t("add_entry.done")) }
                    }
                    .fontWeight(.semibold)
                    .disabled(!isValid || normalizedNickname.count > 32 || normalizedBio.count > 160 || !isValidWebsite || isSaving || !hasChanges)
                }
            }
            .onAppear {
                saveErrorMessage = nil
                username = social.username
                nickname = social.nickname
                bio = social.bio
                website = social.website
            }
        }
    }

    private func save() {
        saveErrorMessage = nil
        isSaving = true
        Task {
            let usernameSaved = normalized == social.username
                ? true
                : await social.updateUsername(normalized, auth: authManager)
            let nicknameSaved: Bool
            if !usernameSaved {
                nicknameSaved = false
            } else if normalizedNickname == social.nickname {
                nicknameSaved = true
            } else {
                nicknameSaved = await social.updateNickname(normalizedNickname, auth: authManager)
            }
            let detailsNeedSaving = normalizedBio != social.bio || normalizedWebsite != social.website || social.needsBioPublication
            let detailsSaved: Bool
            if !nicknameSaved {
                detailsSaved = false
            } else if detailsNeedSaving {
                detailsSaved = await social.updatePublicDetails(bio: normalizedBio, website: normalizedWebsite, auth: authManager)
            } else {
                detailsSaved = true
            }
            isSaving = false
            if detailsSaved { dismiss() }
            else { saveErrorMessage = social.errorMessage }
        }
    }
}

struct TrainingUsernameView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var language: LanguageStore
    @EnvironmentObject private var authManager: AuthManager
    @ObservedObject var social: TrainingSocialStore
    @State private var username = ""
    @State private var isSaving = false
    @State private var saveErrorMessage: String?
    private func t(_ key: String, _ arguments: CVarArg...) -> String { language.text(key, arguments) }
    private var normalized: String { username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    private var isValid: Bool { normalized.range(of: "^[a-z0-9_]{3,24}$", options: .regularExpression) != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("@").foregroundStyle(.secondary)
                        TextField(t("training.social.username"), text: $username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .disabled(isSaving)
                    }
                } footer: { Text(t("training.social.username_rules")) }
                if isSaving {
                    Section {
                        HStack(spacing: HyseSpacing.small) {
                            ProgressView()
                            Text(t("training.social.saving_username")).foregroundStyle(.secondary)
                        }
                    }
                }
                if let error = saveErrorMessage { Section { Text(error).font(.caption).foregroundStyle(HyseColor.warning) } }
            }
            .hyseForm()
            .navigationTitle(t(social.username.isEmpty ? "training.social.create_username" : "training.social.edit_username"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(t("app_tabs.cancel")) { dismiss() }.disabled(isSaving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button { save() } label: {
                        if isSaving { ProgressView() }
                        else { Text(t("recipe_editor.save")) }
                    }
                    .disabled(!isValid || isSaving || normalized == social.username)
                }
            }
            .onAppear {
                saveErrorMessage = nil
                username = social.username
            }
        }
    }

    private func save() {
        saveErrorMessage = nil
        isSaving = true
        Task {
            let saved = await social.updateUsername(normalized, auth: authManager)
            isSaving = false
            if saved { dismiss() }
            else { saveErrorMessage = social.errorMessage }
        }
    }
}
