import SwiftUI
import UIKit
import PhotosUI
import AVFoundation
import UniformTypeIdentifiers
import CoreTransferable
import Charts
import Combine

struct GymCommunityListView: View {
    @EnvironmentObject private var language: LanguageStore
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var store: GymCommunityStore
    @ObservedObject var social: TrainingSocialStore
    @ObservedObject var trainingStore: TrainingStore
    @State private var query = ""
    @State private var showingCreator = false
    private func t(_ key: String, _ arguments: CVarArg...) -> String { language.text(key, arguments) }
    private var joined: [GymCommunity] { store.communities.filter(\.joined) }
    private var discover: [GymCommunity] { store.communities.filter { !$0.joined } }

    var body: some View {
        ZStack {
            HyseBackdrop()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: HyseSpacing.large) {
                    HyseCard(accent: HyseColor.accent) {
                        HStack(spacing: HyseSpacing.medium) {
                            HyseIconBadge(icon: "building.2.fill", size: 48)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(t("training.community.hero")).font(.headline)
                                Text(t("training.community.hero_message")).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    HyseSearchField(placeholder: t("training.community.search"), text: $query)
                    if let error = store.errorMessage {
                        HyseStatusBanner(title: t("training.community.error_title"), message: error, style: .warning, actionTitle: t("content.retry"), action: { Task { await store.load(auth: auth, query: query, force: true) } })
                    }
                    if store.isLoading {
                        ProgressView(t("training.community.loading")).frame(maxWidth: .infinity).padding(.vertical, HyseSpacing.section)
                    } else if store.communities.isEmpty {
                        HyseCard { HyseEmptyState(icon: "building.2", title: t("training.community.empty"), message: t("training.community.empty_message"), actionTitle: t("training.community.create"), action: { showingCreator = true }) }
                    } else {
                        if !joined.isEmpty {
                            communitySection(t("training.community.joined"), communities: joined)
                        }
                        if !discover.isEmpty {
                            communitySection(query.isEmpty ? t("training.community.discover") : t("training.community.results"), communities: discover)
                        }
                    }
                }
                .padding(HyseSpacing.page)
                .padding(.bottom, HyseSpacing.section)
            }
            .refreshable { await store.load(auth: auth, query: query, force: true) }
        }
        .navigationTitle(t("training.community.title"))
        .toolbar { Button { showingCreator = true } label: { Image(systemName: "plus") }.accessibilityLabel(t("training.community.create")) }
        .sheet(isPresented: $showingCreator) { GymCommunityCreateView(store: store) }
        .task(id: query) {
            if !query.isEmpty { try? await Task.sleep(for: .milliseconds(350)) }
            guard !Task.isCancelled else { return }
            await store.load(auth: auth, query: query, force: true)
        }
    }

    private func communitySection(_ title: String, communities: [GymCommunity]) -> some View {
        VStack(alignment: .leading, spacing: HyseSpacing.medium) {
            Text(title).font(.title3.bold())
            ForEach(communities) { community in
                NavigationLink { GymCommunityDetailView(store: store, social: social, trainingStore: trainingStore, initialCommunity: community) } label: {
                    HyseCard(accent: community.joined ? HyseColor.accent : nil) {
                        HStack(spacing: HyseSpacing.medium) {
                            GymCommunityImageView(community: community, size: 54)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(community.name).font(.headline).foregroundStyle(.primary)
                                Text([community.gymName, community.city].filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary)
                                Label(t("training.community.member_count", community.memberCount), systemImage: "person.2")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            if community.joined { Image(systemName: "checkmark.circle.fill").foregroundStyle(HyseColor.accent) }
                            else { Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.secondary) }
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct GymCommunityImageView: View {
    let community: GymCommunity
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(HyseColor.accent.opacity(0.12))
            fallback
            if let data = community.localImageData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
            } else if let url = imageURL {
                AsyncImage(url: url, transaction: Transaction(animation: .easeInOut(duration: 0.2))) { phase in
                    if case let .success(image) = phase {
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: size, height: size)
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(HyseColor.accent.opacity(0.22), lineWidth: 1))
        .accessibilityHidden(true)
    }

    private var imageURL: URL? {
        if let value = community.imageURL, !value.isEmpty {
            return URL(string: value.hasPrefix("http") ? value : HyseConfiguration.serverURL + value)
        }
        guard let filename = community.image, !filename.isEmpty else { return nil }
        var components = URLComponents(string: HyseConfiguration.serverURL)
        components?.path = "/api/files/gym_communities/\(community.id)/\(filename)"
        components?.queryItems = [URLQueryItem(name: "thumb", value: "512x512")]
        return components?.url
    }

    private var fallback: some View {
        Image(systemName: "building.2.fill")
            .font(.system(size: size * 0.38, weight: .semibold))
            .foregroundStyle(HyseColor.accent)
    }
}

private struct GymCommunityCreateView: View {
    private enum CommunityField: Hashable {
        case name, gymName, city, description
    }

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var language: LanguageStore
    @EnvironmentObject private var auth: AuthManager
    @ObservedObject var store: GymCommunityStore
    @State private var name = ""
    @State private var gymName = ""
    @State private var city = ""
    @State private var description = ""
    @State private var isSaving = false
    @State private var photoItem: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var photoError: String?
    @State private var isLoadingPhoto = false
    @FocusState private var focusedField: CommunityField?
    private func t(_ key: String) -> String { language.text(key) }

    var body: some View {
        NavigationStack {
            ZStack {
                HyseBackdrop()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: HyseSpacing.large) {
                        identityCard
                        detailsSection
                        ownerStatus
                        if let photoError {
                            HyseStatusBanner(title: nil, message: photoError, style: .warning)
                        }
                        if let error = store.errorMessage {
                            HyseStatusBanner(title: nil, message: error, style: .warning)
                        }
                    }
                    .padding(HyseSpacing.page)
                    .padding(.bottom, HyseSpacing.section)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .onChange(of: photoItem) { _, item in loadPhoto(item) }
            .navigationTitle(t("training.community.create"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(t("app_tabs.cancel")) { dismiss() } }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                createButtonBar
            }
        }
    }

    private var identityCard: some View {
        HyseCard(accent: HyseColor.accent) {
            VStack(alignment: .leading, spacing: HyseSpacing.large) {
                HStack(alignment: .top, spacing: HyseSpacing.medium) {
                    HyseIconBadge(icon: "sparkles", size: 38)
                    VStack(alignment: .leading, spacing: HyseSpacing.xSmall) {
                        Text(t("training.community.hero"))
                            .font(.title3.bold())
                        Text(t("training.community.hero_message"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                HStack(alignment: .center, spacing: HyseSpacing.large) {
                    communityPhotoPreview
                    VStack(alignment: .leading, spacing: HyseSpacing.small) {
                        Text(name.isEmpty ? t("training.community.name") : name)
                            .font(.headline)
                            .foregroundStyle(name.isEmpty ? .secondary : .primary)
                            .lineLimit(2)
                        Text(gymName.isEmpty ? t("training.community.gym_name") : gymName)
                            .font(.subheadline)
                            .foregroundStyle(gymName.isEmpty ? .secondary : .primary)
                            .lineLimit(1)
                        if !city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Label(city, systemImage: "mappin.and.ellipse")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }

                HStack(spacing: HyseSpacing.small) {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label(photoPickerTitle, systemImage: "photo.badge.plus")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .tint(HyseColor.accent)
                    .disabled(isLoadingPhoto || isSaving)
                    if photoData != nil {
                        Button(role: .destructive, action: removePhoto) {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel(t("training.community.photo.remove"))
                    }
                }
                Text(t("training.community.photo.hint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: HyseSpacing.small) {
            HyseSectionHeading(
                title: t("training.community.details"),
                icon: "building.2.fill"
            )
            HyseCard {
                VStack(spacing: 0) {
                    communityField(t("training.community.name"), icon: "person.3.fill", text: $name, field: .name)
                    Divider().padding(.leading, 40)
                    communityField(t("training.community.gym_name"), icon: "dumbbell.fill", text: $gymName, field: .gymName)
                    Divider().padding(.leading, 40)
                    communityField(t("training.community.city"), icon: "mappin.and.ellipse", text: $city, field: .city)
                    Divider().padding(.leading, 40)
                    communityField(t("training.community.description"), icon: "text.alignleft", text: $description, field: .description, multiline: true)
                }
            }
        }
    }

    private var ownerStatus: some View {
        HyseStatusBanner(
            title: t("training.community.owner_title"),
            message: t("training.community.owner_hint"),
            style: .information
        )
    }

    private var createButtonBar: some View {
        VStack(spacing: 0) {
            Divider()
            Button(action: createCommunity) {
                HStack(spacing: HyseSpacing.small) {
                    if isSaving { ProgressView().tint(.white) }
                    Text(t("training.community.create_action"))
                    if !isSaving { Image(systemName: "arrow.right") }
                }
            }
            .buttonStyle(HysePrimaryButtonStyle())
            .disabled(!canCreate)
            .opacity(canCreate ? 1 : 0.5)
            .padding(.horizontal, HyseSpacing.page)
            .padding(.vertical, HyseSpacing.small)
        }
        .background(HyseColor.elevatedSurface)
    }

    private var photoPickerTitle: String {
        t(photoData == nil ? "training.community.photo.choose" : "training.community.photo.change")
    }

    private func removePhoto() {
        photoData = nil
        photoItem = nil
        photoError = nil
    }

    private var canCreate: Bool {
        !isSaving && !isLoadingPhoto
            && name.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3
            && gymName.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2
    }

    private var communityPhotoPreview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(HyseColor.accent.opacity(0.12))
            if let photoData, let image = UIImage(data: photoData) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "building.2.crop.circle.fill")
                    .font(.system(size: 52, weight: .medium))
                    .foregroundStyle(HyseColor.accent)
            }
            if isLoadingPhoto {
                Color.black.opacity(0.28)
                ProgressView().tint(.white)
            }
        }
        .frame(width: 126, height: 126)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(HyseColor.border))
    }

    @ViewBuilder
    private func communityField(
        _ title: String,
        icon: String,
        text: Binding<String>,
        field: CommunityField,
        multiline: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: HyseSpacing.small) {
            HStack(spacing: HyseSpacing.medium) {
                Image(systemName: icon)
                    .foregroundStyle(HyseColor.accent)
                    .frame(width: 24)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            if multiline {
                TextField("", text: text, axis: .vertical)
                    .lineLimit(3...6)
                    .textFieldStyle(.plain)
                    .focused($focusedField, equals: field)
                    .submitLabel(.done)
            } else {
                TextField("", text: text)
                    .textFieldStyle(.plain)
                    .focused($focusedField, equals: field)
                    .submitLabel(field == .description ? .done : .next)
            }
        }
        .padding(.vertical, HyseSpacing.large)
        .contentShape(Rectangle())
        .onTapGesture { focusedField = field }
        .accessibilityElement(children: .contain)
    }

    private func loadPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        photoError = nil
        isLoadingPhoto = true
        Task { @MainActor in
            defer { isLoadingPhoto = false }
            do {
                guard let originalData = try await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: originalData),
                      let compressed = image.hyseCompressedJPEG(maxDimension: 1_024, maxBytes: 1_500_000)
                else { throw ImageSelectionError.unreadable }
                photoData = compressed
            } catch {
                photoItem = nil
                photoError = t("training.community.photo.error")
            }
        }
    }

    private func createCommunity() {
        guard canCreate else { return }
        isSaving = true
        Task {
            if await store.create(
                name: name,
                gymName: gymName,
                city: city,
                description: description,
                imageData: photoData,
                auth: auth
            ) != nil {
                dismiss()
            }
            isSaving = false
        }
    }
}

private struct GymCommunityMembersView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var language: LanguageStore
    @EnvironmentObject private var auth: AuthManager
    @ObservedObject var store: GymCommunityStore
    let social: TrainingSocialStore
    let trainingStore: TrainingStore
    let initialCommunity: GymCommunity

    private var detail: GymCommunityDetail? { store.detail(initialCommunity.id) }
    private var community: GymCommunity { detail?.community ?? initialCommunity }
    private var members: [GymCommunityMember] { detail?.memberList ?? [] }
    private var canManageRoles: Bool { community.role == "owner" }
    private func t(_ key: String) -> String { language.text(key) }

    var body: some View {
        NavigationStack {
            ZStack {
                HyseBackdrop()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: HyseSpacing.medium) {
                        HyseStatusBanner(
                            title: t(canManageRoles ? "training.community.roles_title" : "training.community.members"),
                            message: t(canManageRoles ? "training.community.roles_owner_hint" : "training.community.roles_view_hint"),
                            style: .information
                        )

                        if members.isEmpty {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, HyseSpacing.section)
                        } else {
                            ForEach(members) { member in
                                memberRow(member)
                            }
                        }

                        if let error = store.errorMessage {
                            HyseStatusBanner(title: nil, message: error, style: .warning)
                        }
                    }
                    .padding(HyseSpacing.page)
                }
                .refreshable {
                    await store.loadDetail(id: community.id, auth: auth, force: true)
                }
            }
            .navigationTitle(t("training.community.members"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(t("add_entry.done")) { dismiss() }
                }
            }
            .task {
                await store.loadDetail(id: community.id, auth: auth, force: members.isEmpty)
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func memberRow(_ member: GymCommunityMember) -> some View {
        HyseCard(accent: member.role == "owner" ? HyseColor.accent : nil) {
            HStack(spacing: HyseSpacing.medium) {
                TrainingProfileLink(userID: member.userID, username: member.username, nickname: member.nickname,
                                    avatar: member.avatar, avatarURL: member.avatarURL, social: social, store: trainingStore) {
                    HStack(spacing: HyseSpacing.medium) {
                        RemoteProfileAvatarView(
                            userID: member.userID,
                            filename: member.avatar,
                            remoteURL: member.avatarURL,
                            size: 46
                        )
                        VStack(alignment: .leading, spacing: 3) {
                            Text(member.displayName.isEmpty ? t("training.community.member") : member.displayName)
                                .font(.headline)
                            if member.userID == auth.accountID {
                                Text(t("training.community.you"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
                roleControl(member)
            }
        }
    }

    @ViewBuilder
    private func roleControl(_ member: GymCommunityMember) -> some View {
        let actionID = "\(community.id):role:\(member.userID)"
        if store.postActionsInFlight.contains(actionID) {
            ProgressView().frame(width: 96)
        } else if canManageRoles && member.role != "owner" {
            Menu {
                Button {
                    updateRole("admin", for: member)
                } label: {
                    Label(t("training.community.role.employee"), systemImage: "person.badge.key.fill")
                }
                Button {
                    updateRole("member", for: member)
                } label: {
                    Label(t("training.community.role.member"), systemImage: "person.fill")
                }
            } label: {
                roleBadge(member.role, editable: true)
            }
        } else {
            roleBadge(member.role, editable: false)
        }
    }

    private func roleBadge(_ role: String, editable: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: roleIcon(role))
            Text(t(roleKey(role)))
            if editable { Image(systemName: "chevron.up.chevron.down").font(.caption2) }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(role == "member" ? Color.secondary : HyseColor.accent)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background((role == "member" ? Color.secondary : HyseColor.accent).opacity(0.11), in: Capsule())
    }

    private func roleKey(_ role: String) -> String {
        role == "owner" ? "training.community.role.owner" : (role == "admin" ? "training.community.role.employee" : "training.community.role.member")
    }

    private func roleIcon(_ role: String) -> String {
        role == "owner" ? "crown.fill" : (role == "admin" ? "person.badge.key.fill" : "person.fill")
    }

    private func updateRole(_ role: String, for member: GymCommunityMember) {
        guard role != member.role else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Task {
            _ = await store.setMemberRole(role, member: member, communityID: community.id, auth: auth)
        }
    }
}

struct GymCommunityDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var language: LanguageStore
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var settings: UserSettingsStore
    @ObservedObject var store: GymCommunityStore
    @ObservedObject var social: TrainingSocialStore
    @ObservedObject var trainingStore: TrainingStore
    let initialCommunity: GymCommunity
    @State private var channel = GymCommunityChannel.news
    @State private var message = ""
    @State private var newsPhotoItems: [PhotosPickerItem] = []
    @State private var newsImageData: [Data] = []
    @State private var newsPhotoError: String?
    @State private var isLoadingNewsPhotos = false
    @State private var newsPhotoLoadID = UUID()
    @State private var isUploadingNews = false
    @State private var newsUploadClientID = UUID().uuidString.lowercased()
    @State private var showingLeaveConfirmation = false
    @State private var showingDeleteCommunityConfirmation = false
    @State private var showingMembers = false
    @State private var showingChallenge = false
    @State private var editingPost: GymCommunityPost?
    @State private var deletingPost: GymCommunityPost?
    @State private var deletingPostInFlight = false
    @State private var replyingTo: GymCommunityPost?
    @State private var actionPost: GymCommunityPost?
    @State private var emphasizedPostID: String?
    @State private var notificationMessage: String?
    @State private var reportTarget: ContentReportTarget?
    @State private var showingReplyUnavailable = false
    @State private var isCheckingReplyTarget = false
    @FocusState private var composerFocused: Bool
    private let reactionChoices = ["👍", "❤️", "🔥", "👏", "💪", "😂"]
    private func t(_ key: String, _ arguments: CVarArg...) -> String { language.text(key, arguments) }
    private var detail: GymCommunityDetail? { store.detail(initialCommunity.id) }
    private var community: GymCommunity { detail?.community ?? initialCommunity }
    private var posts: [GymCommunityPost] { (detail?.posts ?? []).filter { $0.channel == channel } }
    private var canPublish: Bool { channel == .members || community.role == "owner" || community.role == "admin" }
    private var newsNotificationsActive: Bool {
        community.receivesNewsNotifications && settings.communityNewsNotificationsEnabled
    }

    var body: some View {
        ZStack {
            HyseBackdrop()
            communityFeed
        }
        .navigationTitle(community.name)
        .sheet(isPresented: $showingChallenge) {
            GymCommunityChallengeView(community: community)
        }
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if community.joined && canPublish { composer }
        }
        .toolbar {
            if community.joined {
                Button { showingMembers = true } label: {
                    Image(systemName: "person.2.fill")
                }
                .accessibilityLabel(t(community.role == "owner" ? "training.community.manage_members" : "training.community.members"))
                Button { toggleNewsNotifications() } label: {
                    Image(systemName: newsNotificationsActive ? "bell.fill" : "bell.slash")
                }
                .disabled(store.postActionsInFlight.contains("\(community.id):notifications"))
                .accessibilityLabel(t(newsNotificationsActive ? "training.community.notifications_disable" : "training.community.notifications_enable"))
                Menu {
                    Button {
                        reportTarget = .community(id: community.id, name: community.name)
                    } label: {
                        Label(t("content_reports.report_community"), systemImage: "flag")
                    }
                    if community.role == "owner" {
                        Button(t("training.community.delete"), role: .destructive) { showingDeleteCommunityConfirmation = true }
                    } else {
                        Button(t("training.community.leave"), role: .destructive) { showingLeaveConfirmation = true }
                    }
                } label: { Image(systemName: "ellipsis") }
            }
        }
        .alert(t("training.community.notifications_title"), isPresented: Binding(
            get: { notificationMessage != nil },
            set: { if !$0 { notificationMessage = nil } }
        )) {
            Button(t("common.ok")) { notificationMessage = nil }
        } message: {
            Text(notificationMessage ?? "")
        }
        .alert(t("training.community.reply_unavailable_title"), isPresented: $showingReplyUnavailable) {
            Button(t("common.ok")) {}
        } message: {
            Text(t("training.community.reply_unavailable_message"))
        }
        .alert(t("training.community.leave_title"), isPresented: $showingLeaveConfirmation) {
            Button(t("app_tabs.cancel"), role: .cancel) {}
            Button(t("training.community.leave"), role: .destructive) { Task { _ = await store.leave(community, auth: auth) } }
        } message: { Text(t("training.community.leave_message")) }
        .confirmationDialog(
            t("training.community.delete_title"),
            isPresented: $showingDeleteCommunityConfirmation,
            titleVisibility: .visible
        ) {
            Button(t("training.community.delete"), role: .destructive) {
                Task { if await store.deleteCommunity(community, auth: auth) { dismiss() } }
            }
            Button(t("app_tabs.cancel"), role: .cancel) {}
        } message: {
            Text(t("training.community.delete_confirmation"))
        }
        .sheet(item: $editingPost) { post in
            GymCommunityPostEditor(post: post) { text, keepImages, newImages in
                await store.edit(post, text: text, keepImages: keepImages, newImages: newImages, auth: auth)
            }
        }
        .sheet(item: $actionPost) { post in
            communityPostActionsSheet(post)
        }
        .sheet(item: $deletingPost) { post in
            deleteMessageConfirmationSheet(post)
        }
        .sheet(item: $reportTarget) { target in
            ContentReportSheet(target: target)
        }
        .sheet(isPresented: $showingMembers) {
            GymCommunityMembersView(store: store, social: social, trainingStore: trainingStore, initialCommunity: community)
        }
        .onChange(of: channel) { _, _ in
            replyingTo = nil
            newsPhotoItems = []
            newsImageData = []
            newsPhotoError = nil
            newsPhotoLoadID = UUID()
            isLoadingNewsPhotos = false
            newsUploadClientID = UUID().uuidString.lowercased()
        }
        .onChange(of: newsPhotoItems) { _, items in loadNewsPhotos(items) }
        .onChange(of: detail?.posts.map(\.id) ?? []) { _, availablePostIDs in
            guard let replyingTo, !availablePostIDs.contains(replyingTo.id) else { return }
            // An active pre-send refresh performs the same cancellation after
            // it resumes, avoiding duplicate alerts and haptics.
            guard !isCheckingReplyTarget else { return }
            cancelUnavailableReply()
        }
        .task { await store.loadDetail(id: community.id, auth: auth, force: true) }
    }

    private var communityFeed: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: HyseSpacing.large) {
                communityHeader
                if community.joined {
                    Button { showingChallenge = true } label: {
                        HyseCard(accent: HyseColor.accent) {
                            HStack(spacing: HyseSpacing.medium) {
                                Image(systemName: "figure.strengthtraining.traditional")
                                    .foregroundStyle(HyseColor.accent)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(t("challenge.title")).font(.headline)
                                    Text(t("challenge.card_subtitle")).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                if let error = store.errorMessage {
                    HyseStatusBanner(title: t("training.community.error_title"), message: error, style: .warning, actionTitle: t("content.retry"), action: { Task { await store.loadDetail(id: community.id, auth: auth, force: true) } })
                }
                if community.joined { communityConversation }
            }
            .padding(HyseSpacing.page)
            .padding(.bottom, community.joined && canPublish ? 92 : HyseSpacing.section)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .scrollBounceBehavior(.always)
        .scrollDismissesKeyboard(.interactively)
        .refreshable { await store.loadDetail(id: community.id, auth: auth, force: true) }
    }

    private var communityConversation: some View {
        VStack(alignment: .leading, spacing: HyseSpacing.large) {
            HyseSegmentedControl(
                items: GymCommunityChannel.allCases,
                selection: $channel,
                title: { t($0.localizationKey) },
                symbol: { $0 == .news ? "megaphone.fill" : "bubble.left.and.bubble.right.fill" }
            )
            .disabled(isUploadingNews)
            conversationHeader
            communityPosts
        }
    }

    @ViewBuilder private var communityPosts: some View {
        if posts.isEmpty {
            HyseCard {
                HyseEmptyState(
                    icon: channel == .news ? "megaphone" : "bubble.left.and.bubble.right",
                    title: t("training.community.no_posts"),
                    message: t(channel == .news ? "training.community.no_news_message" : "training.community.no_chat_message")
                )
            }
        } else {
            VStack(alignment: .leading, spacing: channel == .members ? HyseSpacing.small : HyseSpacing.large) {
                ForEach(posts) { post in postRow(post) }
            }
        }
    }

    private func toggleNewsNotifications() {
        let shouldEnable = !newsNotificationsActive
        Task {
            if shouldEnable {
                let allowed = await CommunityPushNotificationManager.shared.requestAndRegister(auth: auth)
                guard allowed else {
                    notificationMessage = t("training.community.notifications_denied")
                    return
                }
                settings.communityNewsNotificationsEnabled = true
                await HyseNotificationService.shared.updatePreferences(settings: settings, token: auth.token)
            }
            if await store.setNewsNotifications(shouldEnable, for: community, auth: auth) {
                notificationMessage = t(shouldEnable ? "training.community.notifications_enabled_message" : "training.community.notifications_disabled_message")
            }
        }
    }

    private var communityHeader: some View {
        HyseCard(accent: HyseColor.accent) {
            VStack(alignment: .leading, spacing: HyseSpacing.medium) {
                HStack(spacing: HyseSpacing.medium) {
                    GymCommunityImageView(community: community, size: 64)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(community.name).font(.title2.bold())
                        Text([community.gymName, community.city].filter { !$0.isEmpty }.joined(separator: " · ")).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                if !community.description.isEmpty { Text(community.description).font(.subheadline) }
                HStack {
                    Label(t("training.community.member_count", community.memberCount), systemImage: "person.2.fill")
                    Spacer()
                    if !community.joined {
                        Button(t("training.community.join")) { joinCommunity() }
                            .buttonStyle(.borderedProminent).tint(HyseColor.accent)
                    } else {
                        Label(t(roleLocalizationKey(community.role)), systemImage: "checkmark.circle.fill")
                            .foregroundStyle(HyseColor.accent)
                    }
                }
                .font(.caption.weight(.semibold))
            }
        }
    }

    private func joinCommunity() {
        Task {
            guard await store.join(community, auth: auth) else { return }
            guard await SocialNotificationDefaults.enable(
                communityNews: true,
                settings: settings,
                auth: auth
            ) else {
                notificationMessage = t("training.community.notifications_denied")
                return
            }
            _ = await store.setNewsNotifications(true, for: community, auth: auth)
        }
    }

    private var conversationHeader: some View {
        HStack(spacing: HyseSpacing.medium) {
            HyseIconBadge(
                icon: channel == .news ? "megaphone.fill" : "bubble.left.and.bubble.right.fill",
                size: 36
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(t(channel.localizationKey))
                    .font(.headline)
                Text(channel == .news
                     ? t("training.community.gym_team")
                     : t("training.community.member_count", community.memberCount))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, HyseSpacing.small)
        .accessibilityElement(children: .combine)
    }

    private func roleLocalizationKey(_ role: String) -> String {
        switch role {
        case "owner": "training.community.role.owner"
        case "admin": "training.community.role.employee"
        default: "training.community.role.member"
        }
    }

    private func postRow(_ post: GymCommunityPost) -> some View {
        Group {
            if post.channel == .members {
                memberChatRow(post)
            } else {
                newsPostRow(post)
            }
        }
        .scaleEffect(messageScale(for: post))
        .shadow(
            color: emphasizedPostID == post.id ? Color.black.opacity(0.32) : .clear,
            radius: emphasizedPostID == post.id ? 18 : 0,
            y: emphasizedPostID == post.id ? 9 : 0
        )
        .zIndex(emphasizedPostID == post.id ? 10 : 0)
        // Keep the long press simultaneous with the surrounding ScrollView.
        // A regular onLongPressGesture can win the gesture arena for a full
        // message row and make a message-filled community feel unscrollable.
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.24, maximumDistance: 12)
                .onEnded { _ in presentPostActions(for: post) }
        )
    }

    private func memberChatRow(_ post: GymCommunityPost) -> some View {
        let isOwnMessage = post.authorID == auth.accountID
        return Group {
            if isOwnMessage {
                HStack(alignment: .top, spacing: HyseSpacing.small) {
                    Spacer(minLength: 42)
                    memberChatBubble(post, isOwnMessage: true)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            } else {
                HStack(alignment: .top, spacing: HyseSpacing.small) {
                    TrainingProfileLink(userID: post.authorID, username: post.authorUsername, nickname: post.authorNickname,
                                        avatar: post.avatar, avatarURL: post.avatarURL, social: social, store: trainingStore) {
                        RemoteProfileAvatarView(userID: post.authorID, filename: post.avatar, remoteURL: post.avatarURL, size: 30)
                    }
                    memberChatBubble(post, isOwnMessage: false)
                    Spacer(minLength: 12)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .contentShape(Rectangle())
    }

    private func memberChatBubble(_ post: GymCommunityPost, isOwnMessage: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            TrainingProfileLink(userID: post.authorID, username: post.authorUsername, nickname: post.authorNickname,
                                avatar: post.avatar, avatarURL: post.avatarURL, social: social, store: trainingStore) {
                Text(post.authorDisplayName.isEmpty ? t("training.community.member") : post.authorDisplayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isOwnMessage ? HyseColor.accent : .secondary)
            }
            if let reply = post.reply {
                chatReplyPreview(reply)
            }
            Text(post.body)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 5) {
                if let date = post.date { Text(date, style: .relative) }
                if post.wasEdited { Text(t("training.community.edited")) }
                if isOwnMessage { messageDeliveryStatus(post) }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            reactionSummary(post, fillsWidth: false)
        }
        .padding(.horizontal, HyseSpacing.medium)
        .padding(.vertical, HyseSpacing.medium)
        .background(
            isOwnMessage ? HyseColor.accent.opacity(0.20) : HyseColor.elevatedSurface,
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isOwnMessage ? HyseColor.accent.opacity(0.32) : HyseColor.border, lineWidth: 0.75)
        )
        // Short messages hug their content while long messages wrap naturally.
        .frame(maxWidth: 330, alignment: .leading)
    }

    private func chatReplyPreview(_ reply: GymCommunityReplyPreview) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            replyAuthorLink(reply)
            Text(reply.body)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.horizontal, HyseSpacing.small)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(alignment: .leading) {
            Capsule().fill(HyseColor.accent).frame(width: 3).padding(.vertical, 5)
        }
    }

    @ViewBuilder private func replyAuthorLink(_ reply: GymCommunityReplyPreview) -> some View {
        let name = reply.authorDisplayName.isEmpty ? t("training.community.member") : reply.authorDisplayName
        let loadedAuthor = detail?.posts.first(where: { $0.id == reply.id })
        if let authorID = reply.authorID ?? loadedAuthor?.authorID, !authorID.isEmpty {
            TrainingProfileLink(userID: authorID, username: reply.authorUsername, nickname: reply.authorNickname,
                                avatar: loadedAuthor?.avatar, avatarURL: loadedAuthor?.avatarURL, social: social, store: trainingStore) {
                Text(name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(HyseColor.accent)
            }
        } else {
            Text(name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(HyseColor.accent)
        }
    }

    @ViewBuilder private func messageDeliveryStatus(_ post: GymCommunityPost) -> some View {
        if post.isWaitingForServer {
            ProgressView().controlSize(.mini)
                .accessibilityLabel(t("training.community.sending"))
        } else if post.deliveryState == .failed {
            Button { store.retryMessage(post, auth: auth) } label: {
                Label(t("training.community.send_failed"), systemImage: "exclamationmark.circle")
            }
            .foregroundStyle(HyseColor.danger)
        } else {
            Image(systemName: "checkmark")
                .foregroundStyle(HyseColor.accent)
                .accessibilityLabel(t("training.community.sent"))
        }
    }

    private func newsPostRow(_ post: GymCommunityPost) -> some View {
        HyseCard(accent: post.pinned ? HyseColor.accent : nil) {
            HStack(alignment: .top, spacing: HyseSpacing.medium) {
                TrainingProfileLink(userID: post.authorID, username: post.authorUsername, nickname: post.authorNickname,
                                    avatar: post.avatar, avatarURL: post.avatarURL, social: social, store: trainingStore) {
                    RemoteProfileAvatarView(userID: post.authorID, filename: post.avatar, remoteURL: post.avatarURL, size: 38)
                }
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        TrainingProfileLink(userID: post.authorID, username: post.authorUsername, nickname: post.authorNickname,
                                            avatar: post.avatar, avatarURL: post.avatarURL, social: social, store: trainingStore) {
                            Text(post.authorDisplayName.isEmpty ? t(post.channel == .news ? "training.community.gym_team" : "training.community.member") : post.authorDisplayName).font(.subheadline.bold())
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 1) {
                            if let date = post.date { Text(date, style: .relative) }
                            if post.wasEdited { Text(t("training.community.edited")) }
                            if post.authorID == auth.accountID { messageDeliveryStatus(post) }
                        }
                        .font(.caption2).foregroundStyle(.secondary)
                    }
                    if let reply = post.reply {
                        VStack(alignment: .leading, spacing: 2) {
                            replyAuthorLink(reply)
                            Text(reply.body)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, HyseSpacing.small)
                        .padding(.vertical, 7)
                        .background(HyseColor.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .overlay(alignment: .leading) {
                            Capsule().fill(HyseColor.accent).frame(width: 3).padding(.vertical, 5)
                        }
                    }
                    Text(post.body)
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let imageURLs = post.imageURLs, !imageURLs.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: HyseSpacing.small) {
                                ForEach(imageURLs, id: \.self) { value in
                                    if let url = URL(string: value.hasPrefix("http") ? value : HyseConfiguration.serverURL + value) {
                                        AsyncImage(url: url) { phase in
                                            if case let .success(image) = phase {
                                                image.resizable().scaledToFill()
                                            } else {
                                                RoundedRectangle(cornerRadius: HyseRadius.control)
                                                    .fill(HyseColor.accent.opacity(0.08))
                                                    .overlay { Image(systemName: "photo").foregroundStyle(.secondary) }
                                            }
                                        }
                                        .frame(width: 220, height: 170)
                                        .clipShape(RoundedRectangle(cornerRadius: HyseRadius.control))
                                        .accessibilityLabel(t("training.community.news_image"))
                                    }
                                }
                            }
                        }
                    }
                    reactionSummary(post)
                }
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: HyseRadius.card, style: .continuous))
    }

    private func communityPostActionsSheet(_ post: GymCommunityPost) -> some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.55))
                        .frame(width: 38, height: 5)
                        .padding(.top, 10)
                        .padding(.bottom, HyseSpacing.medium)

                    HStack(alignment: .top, spacing: HyseSpacing.medium) {
                        TrainingProfileLink(userID: post.authorID, username: post.authorUsername, nickname: post.authorNickname,
                                            avatar: post.avatar, avatarURL: post.avatarURL, social: social, store: trainingStore) {
                            RemoteProfileAvatarView(userID: post.authorID, filename: post.avatar, remoteURL: post.avatarURL, size: 38)
                        }
                        VStack(alignment: .leading, spacing: 5) {
                            TrainingProfileLink(userID: post.authorID, username: post.authorUsername, nickname: post.authorNickname,
                                                avatar: post.avatar, avatarURL: post.avatarURL, social: social, store: trainingStore) {
                                Text(post.authorDisplayName.isEmpty ? t("training.community.member") : post.authorDisplayName)
                                    .font(.subheadline.bold())
                            }
                            Text(post.body)
                                .font(.subheadline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(HyseSpacing.medium)
                    .background(HyseColor.elevatedSurface.opacity(0.75), in: RoundedRectangle(cornerRadius: HyseRadius.card, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: HyseRadius.card, style: .continuous).stroke(HyseColor.border))
                    .padding(.horizontal, HyseSpacing.page)
                    .padding(.bottom, HyseSpacing.medium)

                    HStack(spacing: 0) {
                        ForEach(reactionChoices, id: \.self) { emoji in
                            Button {
                                actionPost = nil
                                Task { await store.toggleReaction(emoji, on: post, auth: auth) }
                            } label: {
                                Text(emoji)
                                    .font(.system(size: 27))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 52)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(store.postActionsInFlight.contains("\(post.id):\(emoji)"))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 6)
                    .background(HyseColor.elevatedSurface, in: RoundedRectangle(cornerRadius: HyseRadius.control, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: HyseRadius.control, style: .continuous).stroke(HyseColor.border))
                    .padding(.horizontal, HyseSpacing.page)
                    .padding(.bottom, HyseSpacing.medium)

                    VStack(spacing: 0) {
                        Button { closePostActionsThen { beginReply(to: post) } } label: {
                            communityPostActionRow(t("training.community.reply"), icon: "arrowshape.turn.up.left")
                        }
                        Divider().padding(.leading, 58)
                        Button {
                            UIPasteboard.general.string = "\(copyAuthorName(for: post)): \(post.body)"
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                            actionPost = nil
                        } label: {
                            communityPostActionRow(t("training.community.copy_message"), icon: "doc.on.doc")
                        }
                        Divider().padding(.leading, 58)
                        Button { closePostActionsThen { reportTarget = .message(id: post.id, name: copyAuthorName(for: post)) } } label: {
                            communityPostActionRow(t("content_reports.report_message"), icon: "flag")
                        }
                        Divider().padding(.leading, 58)
                        Button { closePostActionsThen { reportTarget = .profile(id: post.authorID, name: copyAuthorName(for: post)) } } label: {
                            communityPostActionRow(t("content_reports.report_profile"), icon: "person.crop.circle.badge.exclamationmark")
                        }
                        if post.avatar?.isEmpty == false {
                            Divider().padding(.leading, 58)
                            Button { closePostActionsThen { reportTarget = .avatar(id: post.authorID, name: copyAuthorName(for: post)) } } label: {
                                communityPostActionRow(t("content_reports.report_avatar"), icon: "photo.badge.exclamationmark")
                            }
                        }
                        if canEdit(post) {
                            Divider().padding(.leading, 58)
                            Button { closePostActionsThen { editingPost = post } } label: {
                                communityPostActionRow(t("training.community.edit_message"), icon: "pencil")
                            }
                        }
                        if canDelete(post) {
                            Divider().padding(.leading, 58)
                            Button(role: .destructive) { closePostActionsThen { deletingPost = post } } label: {
                                communityPostActionRow(t("training.community.delete_message"), icon: "trash", color: .red)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .background(HyseColor.elevatedSurface, in: RoundedRectangle(cornerRadius: HyseRadius.card, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: HyseRadius.card, style: .continuous).stroke(HyseColor.border))
                    .padding(.horizontal, HyseSpacing.page)
                    .padding(.bottom, HyseSpacing.large)
                }
            }
            .scrollIndicators(.hidden)
            .background(HyseBackdrop())
            .toolbar(.hidden, for: .navigationBar)
        }
        .presentationDetents([.height(canEdit(post) || canDelete(post) ? 590 : 455)])
        .presentationDragIndicator(.hidden)
    }

    private func deleteMessageConfirmationSheet(_ post: GymCommunityPost) -> some View {
        NavigationStack {
            VStack(spacing: HyseSpacing.large) {
                Capsule()
                    .fill(Color.secondary.opacity(0.55))
                    .frame(width: 38, height: 5)
                    .padding(.top, 10)

                ZStack {
                    Circle().fill(Color.red.opacity(0.13))
                    Image(systemName: "trash.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.red)
                }
                .frame(width: 66, height: 66)

                VStack(spacing: HyseSpacing.small) {
                    Text(t("training.community.delete_message_title"))
                        .font(.title2.bold())
                    Text(t("training.community.delete_message_confirmation"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                HStack(alignment: .top, spacing: HyseSpacing.small) {
                    Image(systemName: "quote.opening")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(post.body)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(HyseSpacing.medium)
                .background(HyseColor.elevatedSurface.opacity(0.75), in: RoundedRectangle(cornerRadius: HyseRadius.control, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: HyseRadius.control, style: .continuous).stroke(HyseColor.border))

                VStack(spacing: HyseSpacing.small) {
                    Button(role: .destructive) {
                        deleteCommunityPost(post)
                    } label: {
                        HStack(spacing: HyseSpacing.small) {
                            if deletingPostInFlight { ProgressView().tint(.white) }
                            else { Image(systemName: "trash.fill") }
                            Text(t("training.community.delete_message"))
                        }
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.red, in: RoundedRectangle(cornerRadius: HyseRadius.control, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(deletingPostInFlight)

                    Button(t("app_tabs.cancel")) {
                        deletingPost = nil
                    }
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(HyseColor.elevatedSurface, in: RoundedRectangle(cornerRadius: HyseRadius.control, style: .continuous))
                    .buttonStyle(.plain)
                    .disabled(deletingPostInFlight)
                }
            }
            .padding(.horizontal, HyseSpacing.page)
            .padding(.bottom, HyseSpacing.large)
            .background(HyseBackdrop())
            .toolbar(.hidden, for: .navigationBar)
        }
        .presentationDetents([.height(465)])
        .presentationDragIndicator(.hidden)
        .interactiveDismissDisabled(deletingPostInFlight)
    }

    private func deleteCommunityPost(_ post: GymCommunityPost) {
        guard !deletingPostInFlight else { return }
        deletingPostInFlight = true
        Task {
            let deleted = await store.delete(post, auth: auth)
            deletingPostInFlight = false
            if deleted { deletingPost = nil }
        }
    }

    private func communityPostActionRow(_ title: String, icon: String, color: Color = .primary) -> some View {
        HStack(spacing: HyseSpacing.large) {
            Image(systemName: icon).font(.title3).frame(width: 28)
            Text(title).font(.body)
            Spacer()
        }
        .foregroundStyle(color)
        .padding(.horizontal, HyseSpacing.large)
        .frame(height: 62)
        .contentShape(Rectangle())
    }

    private func closePostActionsThen(_ action: @escaping @MainActor () -> Void) {
        actionPost = nil
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            action()
        }
    }

    private func canEdit(_ post: GymCommunityPost) -> Bool { post.authorID == auth.accountID }
    private func canDelete(_ post: GymCommunityPost) -> Bool {
        canEdit(post) || community.role == "owner" || community.role == "admin"
    }

    private func presentPostActions(for post: GymCommunityPost) {
        guard actionPost == nil, !post.isWaitingForServer, post.deliveryState != .failed else { return }
        let feedback = UIImpactFeedbackGenerator(style: .medium)
        feedback.prepare()
        feedback.impactOccurred(intensity: 0.9)
        withAnimation(.spring(response: 0.24, dampingFraction: 0.58)) {
            emphasizedPostID = post.id
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(115))
            actionPost = post
            withAnimation(.easeOut(duration: 0.16)) {
                emphasizedPostID = nil
            }
        }
    }

    private func messageScale(for post: GymCommunityPost) -> CGFloat {
        if emphasizedPostID == post.id { return 1.035 }
        return 1
    }

    private func copyAuthorName(for post: GymCommunityPost) -> String {
        let displayName = post.authorDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !displayName.isEmpty { return displayName }
        return t(post.channel == .news ? "training.community.gym_team" : "training.community.member")
    }

    private func beginReply(to post: GymCommunityPost) {
        guard posts.contains(where: { $0.id == post.id }) else {
            cancelUnavailableReply()
            return
        }
        replyingTo = post
        Task { @MainActor in
            await Task.yield()
            composerFocused = true
        }
    }

    @ViewBuilder private func reactionSummary(_ post: GymCommunityPost, fillsWidth: Bool = true) -> some View {
        if let reactions = post.reactions, !reactions.isEmpty {
            HStack(spacing: HyseSpacing.small) {
                ForEach(reactions) { reaction in
                    Text("\(reaction.emoji) \(reaction.count)")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(reaction.reacted ? HyseColor.accent.opacity(0.18) : Color.primary.opacity(0.06), in: Capsule())
                        .overlay(Capsule().stroke(reaction.reacted ? HyseColor.accent.opacity(0.55) : HyseColor.border, lineWidth: 0.75))
                }
            }
            .frame(maxWidth: fillsWidth ? .infinity : nil, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }

    private var composer: some View {
        VStack(spacing: 0) {
            if channel == .news {
                VStack(alignment: .leading, spacing: HyseSpacing.small) {
                    if !newsImageData.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: HyseSpacing.small) {
                                ForEach(Array(newsImageData.enumerated()), id: \.offset) { index, data in
                                    if let image = UIImage(data: data) {
                                        Image(uiImage: image)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 74, height: 74)
                                            .clipShape(RoundedRectangle(cornerRadius: 10))
                                            .overlay(alignment: .topTrailing) {
                                                Button {
                                                    newsImageData.remove(at: index)
                                                    newsUploadClientID = UUID().uuidString.lowercased()
                                                } label: {
                                                    Image(systemName: "xmark.circle.fill")
                                                        .foregroundStyle(.white)
                                                        .background(.black.opacity(0.6), in: Circle())
                                                }
                                                .disabled(isUploadingNews)
                                                .accessibilityLabel(t("training.community.photo.remove"))
                                                .padding(4)
                                            }
                                    }
                                }
                            }
                        }
                    }
                    if newsImageData.count < 4 {
                        PhotosPicker(selection: $newsPhotoItems, maxSelectionCount: 4 - newsImageData.count, matching: .images) {
                            Label(t("training.community.news_add_images"), systemImage: "photo.badge.plus")
                                .font(.subheadline.weight(.semibold))
                        }
                        .disabled(isLoadingNewsPhotos || isUploadingNews)
                    }
                    if isLoadingNewsPhotos { ProgressView() }
                    if let newsPhotoError {
                        Text(newsPhotoError).font(.caption).foregroundStyle(.red)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, HyseSpacing.page)
                .padding(.vertical, HyseSpacing.small)
            }
            if let replyingTo {
                HStack(spacing: HyseSpacing.small) {
                    Image(systemName: "arrowshape.turn.up.left.fill").foregroundStyle(HyseColor.accent)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(t("training.community.replying_to", replyAuthor(replyingTo)))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(HyseColor.accent)
                        Text(replyingTo.body).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Button { self.replyingTo = nil } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(t("app_tabs.cancel"))
                }
                .padding(.horizontal, HyseSpacing.page)
                .padding(.vertical, HyseSpacing.small)
                .background(HyseColor.accent.opacity(0.07))
                Divider()
            }
            HStack(spacing: HyseSpacing.small) {
                TextField(t(channel == .news ? "training.community.news_placeholder" : "training.community.message_placeholder"), text: $message, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.plain)
                    .textInputAutocapitalization(.sentences)
                    .submitLabel(.send)
                    .focused($composerFocused)
                    .onSubmit { sendCommunityMessage() }
                    .disabled(isUploadingNews)
                Button {
                    sendCommunityMessage()
                } label: {
                    Group {
                        if isCheckingReplyTarget || isUploadingNews {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "arrow.up").font(.headline.bold()).foregroundStyle(.white)
                        }
                    }
                    .frame(width: 42, height: 42)
                    .background(canSendMessage ? HyseColor.accent : Color.secondary.opacity(0.25), in: Circle())
                }
                .disabled(!canSendMessage)
                .accessibilityLabel(t("training.community.send"))
            }
            .padding(.horizontal, HyseSpacing.medium)
            .padding(.vertical, HyseSpacing.small)
            .background(HyseColor.elevatedSurface, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 19, style: .continuous).stroke(HyseColor.border))
            .padding(.horizontal, HyseSpacing.page)
            .padding(.vertical, HyseSpacing.small)
        }
        .background(HyseColor.elevatedSurface)
        .overlay(alignment: .top) { Divider() }
    }

    private var canSendMessage: Bool {
        !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && message.utf16.count <= 2000
            && !isCheckingReplyTarget
            && !isUploadingNews
            && !isLoadingNewsPhotos
            && replyTargetIsAvailable
    }

    private func replyAuthor(_ post: GymCommunityPost) -> String {
        post.authorDisplayName.isEmpty ? t(post.channel == .news ? "training.community.gym_team" : "training.community.member") : post.authorDisplayName
    }

    private var replyTargetIsAvailable: Bool {
        guard let replyingTo else { return true }
        return posts.contains(where: { $0.id == replyingTo.id })
    }

    private func sendCommunityMessage() {
        let value = message
        let reply = replyingTo
        guard replyTargetIsAvailable else {
            cancelUnavailableReply()
            return
        }

        if channel == .news && !newsImageData.isEmpty {
            guard !isUploadingNews, !isLoadingNewsPhotos else { return }
            isUploadingNews = true
            let images = newsImageData
            let clientID = newsUploadClientID
            Task {
                let published = await store.publishNewsWithImages(
                    value, images: images, communityID: community.id,
                    replyTo: reply, clientID: clientID, auth: auth
                )
                isUploadingNews = false
                if published {
                    message = ""
                    replyingTo = nil
                    newsPhotoItems = []
                    newsImageData = []
                    newsPhotoError = nil
                    newsUploadClientID = UUID().uuidString.lowercased()
                }
            }
            return
        }

        if store.send(value, channel: channel, communityID: community.id, replyTo: reply, auth: auth) {
            message = ""
            replyingTo = nil
        }
    }

    private func loadNewsPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        let loadID = UUID()
        newsPhotoLoadID = loadID
        isLoadingNewsPhotos = true
        newsPhotoError = nil
        Task { @MainActor in
            defer {
                if newsPhotoLoadID == loadID {
                    newsPhotoItems = []
                    isLoadingNewsPhotos = false
                }
            }
            for item in items.prefix(4 - newsImageData.count) {
                do {
                    guard let original = try await item.loadTransferable(type: Data.self),
                          let image = UIImage(data: original),
                          let compressed = image.hyseCompressedJPEG(maxDimension: 1_600, maxBytes: 1_500_000)
                    else { throw ImageSelectionError.unreadable }
                    guard newsPhotoLoadID == loadID, channel == .news else { return }
                    newsImageData.append(compressed)
                    newsUploadClientID = UUID().uuidString.lowercased()
                } catch {
                    guard newsPhotoLoadID == loadID, channel == .news else { return }
                    newsPhotoError = t("training.community.photo.error")
                }
            }
        }
    }

    private func cancelUnavailableReply() {
        replyingTo = nil
        isCheckingReplyTarget = false
        showingReplyUnavailable = true
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}

private struct GymCommunityPostEditor: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var language: LanguageStore
    let post: GymCommunityPost
    let save: (String, [String], [Data]) async -> Bool
    @State private var text: String
    @State private var retainedImages: [String]
    @State private var newImageData: [Data] = []
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var photoError: String?
    @State private var isLoadingPhotos = false
    @State private var isSaving = false
    @FocusState private var editorFocused: Bool

    init(post: GymCommunityPost, save: @escaping (String, [String], [Data]) async -> Bool) {
        self.post = post; self.save = save
        _text = State(initialValue: post.body)
        _retainedImages = State(initialValue: post.images ?? [])
    }

    var body: some View {
        NavigationStack {
            ZStack {
                HyseBackdrop()
                ScrollView {
                    VStack(alignment: .leading, spacing: HyseSpacing.large) {
                        HStack(spacing: HyseSpacing.medium) {
                            ZStack {
                                Circle().fill(HyseColor.accent.opacity(0.15))
                                Image(systemName: "pencil.line")
                                    .font(.title3.bold())
                                    .foregroundStyle(HyseColor.accent)
                            }
                            .frame(width: 46, height: 46)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(language.text("training.community.edit_message"))
                                    .font(.headline)
                                Text(language.text("training.community.edit_message_hint"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        VStack(alignment: .trailing, spacing: HyseSpacing.small) {
                            TextEditor(text: $text)
                                .focused($editorFocused)
                                .font(.body)
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: 170)
                                .padding(HyseSpacing.small)
                                .background(HyseColor.elevatedSurface, in: RoundedRectangle(cornerRadius: HyseRadius.card, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: HyseRadius.card, style: .continuous)
                                        .stroke(editorFocused ? HyseColor.accent : HyseColor.border, lineWidth: editorFocused ? 1.6 : 1)
                                }

                            Text("\(text.count)/2000")
                                .font(.caption.monospacedDigit().weight(.medium))
                                .foregroundStyle(text.count > 2000 ? Color.red : Color.secondary)
                        }

                        if post.channel == .news {
                            newsImageEditor
                        }

                        Button { saveMessage() } label: {
                            HStack(spacing: HyseSpacing.small) {
                                if isSaving {
                                    ProgressView().tint(.white)
                                } else {
                                    Image(systemName: "checkmark")
                                }
                                Text(language.text("training.community.save_message"))
                            }
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(HyseColor.accent, in: RoundedRectangle(cornerRadius: HyseRadius.control, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(!canSave)
                        .opacity(canSave ? 1 : 0.45)
                    }
                    .padding(HyseSpacing.page)
                }
            }
            .navigationTitle(language.text("training.community.edit_message"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(language.text("app_tabs.cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(language.text("training.community.save_message"), action: saveMessage)
                    .fontWeight(.semibold)
                    .disabled(!canSave)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear { editorFocused = true }
        .onChange(of: photoItems) { _, items in loadPhotos(items) }
    }

    private var canSave: Bool {
        !isSaving
            && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && text.count <= 2000
            && !isLoadingPhotos
            && (text != post.body || retainedImages != (post.images ?? []) || !newImageData.isEmpty)
    }

    private var newsImageEditor: some View {
        VStack(alignment: .leading, spacing: HyseSpacing.small) {
            if !retainedImages.isEmpty || !newImageData.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: HyseSpacing.small) {
                        ForEach(retainedImages, id: \.self) { filename in
                            if let url = imageURL(for: filename) {
                                AsyncImage(url: url) { image in
                                    image.resizable().scaledToFill()
                                } placeholder: {
                                    ProgressView()
                                }
                                .frame(width: 82, height: 82)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(alignment: .topTrailing) {
                                    removeImageButton {
                                        retainedImages.removeAll { $0 == filename }
                                    }
                                }
                            }
                        }
                        ForEach(Array(newImageData.enumerated()), id: \.offset) { index, data in
                            if let image = UIImage(data: data) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 82, height: 82)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .overlay(alignment: .topTrailing) {
                                        removeImageButton {
                                            newImageData.remove(at: index)
                                        }
                                    }
                            }
                        }
                    }
                }
            }
            if retainedImages.count + newImageData.count < 4 {
                PhotosPicker(
                    selection: $photoItems,
                    maxSelectionCount: 4 - retainedImages.count - newImageData.count,
                    matching: .images
                ) {
                    Label(language.text("training.community.news_add_images"), systemImage: "photo.badge.plus")
                        .font(.subheadline.weight(.semibold))
                }
                .disabled(isLoadingPhotos || isSaving)
            }
            if isLoadingPhotos { ProgressView() }
            if let photoError {
                Text(photoError).font(.caption).foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func removeImageButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.white)
                .background(.black.opacity(0.6), in: Circle())
        }
        .disabled(isSaving)
        .accessibilityLabel(language.text("training.community.photo.remove"))
        .padding(4)
    }

    private func imageURL(for filename: String) -> URL? {
        guard let index = post.images?.firstIndex(of: filename),
              let urls = post.imageURLs, urls.indices.contains(index) else { return nil }
        let path = urls[index]
        return URL(string: path.hasPrefix("http") ? path : HyseConfiguration.serverURL + path)
    }

    private func loadPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        isLoadingPhotos = true
        photoError = nil
        Task { @MainActor in
            defer {
                photoItems = []
                isLoadingPhotos = false
            }
            for item in items.prefix(4 - retainedImages.count - newImageData.count) {
                do {
                    guard let original = try await item.loadTransferable(type: Data.self),
                          let image = UIImage(data: original),
                          let compressed = image.hyseCompressedJPEG(maxDimension: 1_600, maxBytes: 1_500_000)
                    else { throw ImageSelectionError.unreadable }
                    newImageData.append(compressed)
                } catch {
                    photoError = language.text("training.community.photo.error")
                }
            }
        }
    }

    private func saveMessage() {
        guard canSave else { return }
        isSaving = true
        Task {
            if await save(text, retainedImages, newImageData) {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                dismiss()
            } else {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                isSaving = false
            }
        }
    }
}
