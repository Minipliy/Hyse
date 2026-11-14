import SwiftUI
import PhotosUI
import CryptoKit

struct ProfileAvatarView: View {
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var language: LanguageStore
    let size: CGFloat
    var editable = false

    @State private var selectedPhoto: PhotosPickerItem?
    @State private var imageToEdit: UIImage?
    @State private var showingEditor = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if editable {
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    avatar
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: max(11, size * 0.18), weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(max(5, size * 0.09))
                                .background(HyseColor.accent, in: Circle())
                                .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
                        }
                }
                .buttonStyle(.plain)
                .disabled(authManager.isUploadingAvatar)
                .accessibilityLabel(language.text("profile.change_avatar"))
            } else {
                avatar
            }
        }
        .onChange(of: selectedPhoto) { _, item in
            guard let item else { return }
            Task {
                do {
                    guard let data = try await item.loadTransferable(type: Data.self),
                          let image = UIImage(data: data) else {
                        throw AvatarSelectionError.unreadable
                    }
                    imageToEdit = image
                    showingEditor = true
                } catch {
                    errorMessage = error.localizedDescription
                }
                selectedPhoto = nil
            }
        }
        .sheet(isPresented: $showingEditor, onDismiss: { imageToEdit = nil }) {
            if let imageToEdit {
                ProfileAvatarEditorView(image: imageToEdit) { data in
                    Task {
                        do {
                            try await authManager.updateAvatar(data)
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                }
                .environmentObject(language)
            }
        }
        .alert(language.text("profile.avatar_upload_failed"), isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button(language.text("common.ok")) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var avatar: some View {
        ZStack {
            Circle().fill(HyseColor.accent.opacity(0.14))
            fallback
            if let data = authManager.accountAvatarLocalData, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else if let url = authManager.accountAvatarURL {
                PersistentProfileImage(url: url)
            }
            if authManager.isUploadingAvatar {
                Circle().fill(.black.opacity(0.36))
                ProgressView().tint(.white)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(HyseColor.accent.opacity(0.22), lineWidth: 1))
    }

    private var fallback: some View {
        Image(systemName: "person.fill")
            .resizable()
            .scaledToFit()
            .padding(size * 0.24)
            .foregroundStyle(HyseColor.accent)
    }
}

private struct ProfileAvatarEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var language: LanguageStore
    let image: UIImage
    let save: (Data) -> Void

    @State private var zoom = 1.0
    @State private var offset: CGSize = .zero
    @State private var dragOrigin: CGSize = .zero
    @State private var previewSide: CGFloat = 280

    var body: some View {
        NavigationStack {
            VStack(spacing: HyseSpacing.xLarge) {
                Spacer(minLength: HyseSpacing.medium)
                GeometryReader { proxy in
                    let side = min(proxy.size.width, proxy.size.height, 320)
                    ZStack {
                        HyseColor.surface
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: side, height: side)
                            .scaleEffect(zoom)
                            .offset(offset)
                    }
                    .frame(width: side, height: side)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(HyseColor.border, lineWidth: 1).allowsHitTesting(false))
                    .contentShape(Circle())
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                offset = clamped(
                                    CGSize(
                                        width: dragOrigin.width + value.translation.width,
                                        height: dragOrigin.height + value.translation.height
                                    ),
                                    side: side
                                )
                            }
                            .onEnded { _ in dragOrigin = offset }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onAppear { previewSide = side }
                    .onChange(of: side) { _, newSide in
                        previewSide = newSide
                        offset = clamped(offset, side: newSide)
                        dragOrigin = offset
                    }
                }
                .aspectRatio(1, contentMode: .fit)

                VStack(spacing: HyseSpacing.medium) {
                    HStack {
                        Image(systemName: "minus.magnifyingglass")
                        Slider(value: $zoom, in: 1...4)
                        Image(systemName: "plus.magnifyingglass")
                    }
                    .onChange(of: zoom) { _, _ in
                        offset = clamped(offset, side: previewSide)
                        dragOrigin = offset
                    }
                    Text(language.text("profile.avatar_adjust_hint"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button(language.text("profile.avatar_reset")) {
                        zoom = 1
                        offset = .zero
                        dragOrigin = .zero
                    }
                    .font(.footnote.weight(.semibold))
                }
                .padding(.horizontal, HyseSpacing.xLarge)
                Spacer(minLength: HyseSpacing.medium)
            }
            .background(HyseColor.background)
            .navigationTitle(language.text("profile.avatar_adjust_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(language.text("app_tabs.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(language.text("profile.avatar_use")) {
                        guard let data = renderedAvatarData() else { return }
                        save(data)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private func clamped(_ proposed: CGSize, side: CGFloat) -> CGSize {
        let ratio = max(image.size.width / max(image.size.height, 1), 0.001)
        let baseWidth = ratio >= 1 ? side * ratio : side
        let baseHeight = ratio >= 1 ? side : side / ratio
        let maximumX = max(0, (baseWidth * zoom - side) / 2)
        let maximumY = max(0, (baseHeight * zoom - side) / 2)
        return CGSize(
            width: min(max(proposed.width, -maximumX), maximumX),
            height: min(max(proposed.height, -maximumY), maximumY)
        )
    }

    private func renderedAvatarData() -> Data? {
        let side: CGFloat = 1024
        let ratio = max(image.size.width / max(image.size.height, 1), 0.001)
        let baseSize = ratio >= 1
            ? CGSize(width: side * ratio, height: side)
            : CGSize(width: side, height: side / ratio)
        let drawSize = CGSize(width: baseSize.width * zoom, height: baseSize.height * zoom)
        let offsetScale = side / max(previewSide, 1)
        let drawRect = CGRect(
            x: (side - drawSize.width) / 2 + offset.width * offsetScale,
            y: (side - drawSize.height) / 2 + offset.height * offsetScale,
            width: drawSize.width,
            height: drawSize.height
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let result = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            UIColor.systemBackground.setFill()
            UIRectFill(CGRect(x: 0, y: 0, width: side, height: side))
            image.draw(in: drawRect)
        }
        return result.jpegData(compressionQuality: 0.9)
    }
}

private enum AvatarSelectionError: LocalizedError {
    case unreadable
    var errorDescription: String? { LanguageStore.localizedString("profile.avatar_invalid_image") }
}

struct RemoteProfileAvatarView: View {
    let userID: String?
    let filename: String?
    var remoteURL: String? = nil
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(HyseColor.accent.opacity(0.14))
            fallback
            if let url = avatarURL {
                PersistentProfileImage(url: url)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var avatarURL: URL? {
        if let remoteURL, !remoteURL.isEmpty {
            if remoteURL.hasPrefix("http") { return URL(string: remoteURL) }
            return URL(string: HyseConfiguration.serverURL + remoteURL)
        }
        guard let userID, let filename, !userID.isEmpty, !filename.isEmpty else { return nil }
        var components = URLComponents(string: HyseConfiguration.serverURL)
        components?.path = "/api/files/users/\(userID)/\(filename)"
        components?.queryItems = [URLQueryItem(name: "thumb", value: "256x256")]
        return components?.url
    }

    private var fallback: some View {
        Image(systemName: "person.fill")
            .resizable()
            .scaledToFit()
            .padding(size * 0.25)
            .foregroundStyle(HyseColor.accent)
    }
}

/// Displays the disk copy immediately and contacts the server only when an
/// avatar has never been cached on this device. Application Support keeps the
/// image available offline across app launches.
private struct PersistentProfileImage: View {
    let url: URL
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Color.clear
            }
        }
        .task(id: url.absoluteString) {
            guard let data = await ProfileImageDataCache.shared.data(for: url), !Task.isCancelled else { return }
            image = UIImage(data: data)
        }
    }
}

private actor ProfileImageDataCache {
    static let shared = ProfileImageDataCache()

    private var memory: [String: Data] = [:]
    private var inFlight: [String: Task<Data?, Never>] = [:]
    private let directory: URL?

    init() {
        directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Hyse/ProfileImageCache", isDirectory: true)
        if let directory {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    func data(for url: URL) async -> Data? {
        let downloadURL = canonicalAvatarURL(url)
        let key = cacheKey(downloadURL)
        if let data = memory[key] { return data }
        if let fileURL = directory?.appendingPathComponent(key), let data = try? Data(contentsOf: fileURL) {
            memory[key] = data
            return data
        }
        if let task = inFlight[key] { return await task.value }

        let task = Task<Data?, Never> {
            var request = URLRequest(url: downloadURL)
            request.cachePolicy = .returnCacheDataElseLoad
            request.timeoutInterval = 15
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode),
                  UIImage(data: data) != nil else { return nil }
            return data
        }
        inFlight[key] = task
        let data = await task.value
        inFlight[key] = nil
        if let data {
            memory[key] = data
            if let fileURL = directory?.appendingPathComponent(key) {
                try? data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            }
        }
        return data
    }

    /// All UI variants of the same PocketBase avatar share one on-device file.
    /// Without this normalization, `thumb=128x128`, `thumb=256x256`, and the
    /// unqualified URL would each trigger their own download and disk entry.
    private func canonicalAvatarURL(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.path.contains("/api/files/users/") else { return url }
        var queryItems = (components.queryItems ?? []).filter { $0.name != "thumb" }
        queryItems.append(URLQueryItem(name: "thumb", value: "256x256"))
        components.queryItems = queryItems
        return components.url ?? url
    }

    private func cacheKey(_ url: URL) -> String {
        SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined() + ".image"
    }
}
