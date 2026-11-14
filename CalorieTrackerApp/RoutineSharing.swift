import SwiftUI
import PhotosUI
import UIKit

nonisolated enum RoutineShareLink {
    static let host = HyseConfiguration.serverHost

    static func url(id: String, isGerman: Bool) -> URL? {
        guard validID(id) else { return nil }
        return URL(string: "https://\(host)/\(isGerman ? "de/routine" : "en/routine")/\(id)")
    }

    static func routineID(from url: URL) -> String? {
        let path = url.pathComponents.filter { $0 != "/" }
        let id: String?
        if url.scheme == "hyseapp", url.host == "routine", path.count == 1 {
            id = path[0]
        } else if url.scheme == "https", url.host == host, path.count == 3,
                  (path[0] == "de" || path[0] == "en"), path[1] == "routine" {
            id = path[2]
        } else {
            id = nil
        }
        return id.flatMap { validID($0) ? $0 : nil }
    }

    private static func validID(_ id: String) -> Bool {
        id.count == 15 && id.unicodeScalars.allSatisfy(CharacterSet.alphanumerics.contains)
    }
}

nonisolated struct SharedRoutineSnapshot: Codable, Sendable {
    struct SetPlan: Codable, Sendable {
        let type: TrainingSetType
        let weightKilograms: Double
        let reps: Int
        let durationSeconds: Double
        let distanceMeters: Double
        let assistedKilograms: Double
        let rpe: Double?

        init(_ set: TrainingSetLog) {
            type = set.type
            weightKilograms = set.weightKilograms
            reps = set.reps
            durationSeconds = set.durationSeconds
            distanceMeters = set.distanceMeters
            assistedKilograms = set.assistedKilograms
            rpe = set.rpe
        }

        func makeSet() -> TrainingSetLog {
            TrainingSetLog(type: type, weightKilograms: weightKilograms, reps: reps,
                           durationSeconds: durationSeconds, distanceMeters: distanceMeters,
                           rpe: rpe, assistedKilograms: assistedKilograms)
        }
    }

    struct ExercisePlan: Codable, Sendable {
        let nameKey: String
        let englishName: String
        let germanName: String
        let type: TrainingExerciseType
        let equipment: TrainingEquipment
        let primaryMuscles: [String]
        let secondaryMuscles: [String]
        let isUnilateral: Bool?
        let notes: String
        let restSeconds: Int
        let supersetGroup: String?
        let sets: [SetPlan]

        init(_ placement: RoutineExercise) {
            let exercise = placement.exercise
            nameKey = exercise.isCustom ? "custom" : exercise.nameKey
            englishName = exercise.englishName
            germanName = exercise.germanName
            type = exercise.type
            equipment = exercise.equipment
            primaryMuscles = exercise.primaryMuscles
            secondaryMuscles = exercise.secondaryMuscles
            isUnilateral = exercise.isUnilateral
            notes = placement.notes
            restSeconds = placement.restSeconds
            supersetGroup = placement.supersetGroup
            sets = placement.sets.map(SetPlan.init)
        }

        func makePlacement(catalog: [TrainingExercise]) -> RoutineExercise {
            let existing = nameKey == "custom" ? nil : catalog.first { $0.nameKey == nameKey && !$0.isCustom }
            var exercise = existing ?? TrainingExercise(
                id: UUID(), nameKey: nameKey, englishName: englishName, germanName: germanName,
                descriptionKey: "", techniqueKey: "", type: type, equipment: equipment,
                primaryMuscles: primaryMuscles, secondaryMuscles: secondaryMuscles,
                isCustom: true, isFavorite: false, updatedAt: Date(), isUnilateral: isUnilateral
            )
            if let isUnilateral { exercise.isUnilateral = isUnilateral }
            return RoutineExercise(exercise: exercise, notes: notes,
                                   restSeconds: restSeconds, supersetGroup: supersetGroup,
                                   sets: sets.map { $0.makeSet() })
        }
    }

    let name: String
    let details: String
    let exercises: [ExercisePlan]

    init(_ routine: WorkoutRoutine) {
        name = String(routine.name.prefix(180))
        details = String(routine.details.prefix(4000))
        exercises = routine.exercises.map(ExercisePlan.init)
    }

    func makeRoutine(catalog: [TrainingExercise]) -> WorkoutRoutine {
        WorkoutRoutine(name: name, details: details,
                       exercises: exercises.map { $0.makePlacement(catalog: catalog) })
    }
}

nonisolated struct SharedRoutine: Decodable, Identifiable, Sendable {
    let id: String
    let snapshot: SharedRoutineSnapshot
    let image: String

    enum CodingKeys: String, CodingKey { case id, image; case snapshot = "snapshot_json" }

    var imageURL: URL? {
        guard !image.isEmpty else { return nil }
        return URL(string: "https://\(RoutineShareLink.host)/api/files/routine_shares/\(id)/\(image)")
    }
}

enum RoutineShareError: Error { case invalidResponse, server(Int), uploadFailed, tooLarge }

actor RoutineShareService {
    static let shared = RoutineShareService()
    private let base = "\(HyseConfiguration.serverURL)/api/collections/routine_shares/records"
    private struct PublishedRecord: Decodable { let id: String }

    func publish(routine: WorkoutRoutine, ownerID: String, token: String) async throws -> String {
        guard !ownerID.isEmpty, !token.isEmpty else { throw RoutineShareError.invalidResponse }
        guard routine.exercises.count <= 100,
              routine.exercises.allSatisfy({ $0.sets.count <= 100 }) else { throw RoutineShareError.tooLarge }
        let existingID = routine.shareRecordID.flatMap { RoutineShareLink.url(id: $0, isGerman: true) == nil ? nil : $0 }
        guard let url = URL(string: base + (existingID.map { "/\($0)" } ?? "")) else { throw RoutineShareError.invalidResponse }
        let snapshotData = try JSONEncoder().encode(SharedRoutineSnapshot(routine))
        guard snapshotData.count <= 262_144 else { throw RoutineShareError.tooLarge }
        var payload: [String: Any] = ["snapshot_json": try JSONSerialization.jsonObject(with: snapshotData)]
        if existingID == nil { payload["owner"] = ownerID }
        var request = URLRequest(url: url)
        request.httpMethod = existingID == nil ? "POST" : "PATCH"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let status = (response as? HTTPURLResponse)?.statusCode else { throw RoutineShareError.invalidResponse }
        if status == 404, existingID != nil {
            var fresh = routine
            fresh.shareRecordID = nil
            return try await publish(routine: fresh, ownerID: ownerID, token: token)
        }
        guard (200...299).contains(status) else { throw RoutineShareError.server(status) }
        guard let id = try? JSONDecoder().decode(PublishedRecord.self, from: data).id,
              RoutineShareLink.url(id: id, isGerman: true) != nil else { throw RoutineShareError.invalidResponse }
        if let original = RecipeImageStore.data(for: routine.imageFileName) ?? routine.imageData {
            guard let jpeg = await MainActor.run(body: { UIImage(data: original)?.hyseCompressedJPEG(maxDimension: 1400, maxBytes: 1_800_000) }) else {
                if existingID == nil { try? await revoke(id: id, token: token) }
                throw RoutineShareError.uploadFailed
            }
            do { try await uploadImage(jpeg, id: id, token: token) }
            catch {
                if existingID == nil { try? await revoke(id: id, token: token) }
                throw error
            }
        }
        return id
    }

    func fetch(id: String) async throws -> SharedRoutine {
        guard RoutineShareLink.url(id: id, isGerman: true) != nil,
              let url = URL(string: "https://\(RoutineShareLink.host)/api/hyse/public-routines/\(id)") else {
            throw RoutineShareError.invalidResponse
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw RoutineShareError.invalidResponse }
        return try JSONDecoder().decode(SharedRoutine.self, from: data)
    }

    func revoke(id: String, token: String) async throws {
        guard let url = URL(string: base + "/\(id)") else { throw RoutineShareError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let status = (response as? HTTPURLResponse)?.statusCode,
              (200...299).contains(status) || status == 404 else { throw RoutineShareError.invalidResponse }
    }

    func removeImage(id: String, token: String) async throws {
        guard let url = URL(string: base + "/\(id)") else { throw RoutineShareError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{\"image\":\"\"}".utf8)
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let status = (response as? HTTPURLResponse)?.statusCode, (200...299).contains(status) else {
            throw RoutineShareError.invalidResponse
        }
    }

    private func uploadImage(_ data: Data, id: String, token: String) async throws {
        guard let url = URL(string: base + "/\(id)") else { throw RoutineShareError.invalidResponse }
        let boundary = "HyseRoutine-\(UUID().uuidString)"
        var body = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"image\"; filename=\"routine.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n".utf8)
        body.append(data)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let status = (response as? HTTPURLResponse)?.statusCode, (200...299).contains(status) else {
            throw RoutineShareError.uploadFailed
        }
    }
}

private struct RoutineShareDestination: Identifiable {
    let id = UUID()
    let url: URL
}

private struct RoutineShareActivitySheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct RoutinePhotoView: View {
    let localData: Data?
    let remoteURL: URL?
    let height: CGFloat

    var body: some View {
        GeometryReader { viewport in
            Group {
                if let localData, let image = UIImage(data: localData) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else if let remoteURL {
                    AsyncImage(url: remoteURL) { image in image.resizable().scaledToFill() } placeholder: {
                        Rectangle().fill(HyseColor.elevatedSurface)
                    }
                }
            }
            .frame(width: viewport.size.width, height: height)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: HyseRadius.card))
        }
        .frame(height: height)
    }
}

struct RoutineShareView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var language: LanguageStore
    @EnvironmentObject private var auth: AuthManager
    @ObservedObject var store: TrainingStore
    let routineID: UUID
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isLoadingPhoto = false
    @State private var isPublishing = false
    @State private var showingLogin = false
    @State private var pendingShareAfterLogin = false
    @State private var errorMessage: String?
    @State private var destination: RoutineShareDestination?
    @State private var remoteImageURL: URL?

    private var routine: WorkoutRoutine? { store.routines.first { $0.id == routineID } }
    private func t(_ key: String) -> String { language.text(key) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: HyseSpacing.large) {
                    if let routine {
                        let localPhoto = RecipeImageStore.data(for: routine.imageFileName) ?? routine.imageData
                        if localPhoto != nil || remoteImageURL != nil {
                            RoutinePhotoView(localData: localPhoto, remoteURL: remoteImageURL, height: 220)
                        }
                        Text(routine.name).font(.title.bold())
                        Text(t("training.routine.share_explanation")).foregroundStyle(.secondary)
                        PhotosPicker(selection: $selectedPhoto, matching: .images) {
                            Label(t("training.routine.share_photo"), systemImage: "photo.badge.plus")
                        }.buttonStyle(HyseSecondaryButtonStyle())
                        if routine.imageFileName != nil || routine.imageData != nil || remoteImageURL != nil {
                            Button(role: .destructive) { Task { await removePhoto(routine) } } label: {
                                Label(t("training.routine.remove_photo"), systemImage: "photo.badge.minus")
                            }
                            .disabled(isPublishing || isLoadingPhoto)
                        }
                        Button { Task { await publish(routine) } } label: {
                            if isPublishing || isLoadingPhoto { ProgressView().frame(maxWidth: .infinity) }
                            else { Label(t("training.routine.share_link"), systemImage: "square.and.arrow.up") }
                        }
                        .buttonStyle(HysePrimaryButtonStyle())
                        .disabled(isPublishing || isLoadingPhoto)
                        if routine.shareRecordID != nil {
                            Button(role: .destructive) { Task { await revoke(routine) } } label: {
                                Label(t("training.routine.revoke_link"), systemImage: "link.badge.minus")
                            }
                            .disabled(isPublishing)
                        }
                    }
                }
                .padding(HyseSpacing.page)
            }
            .background(HyseBackdrop())
            .navigationTitle(t("training.routine.share"))
            .navigationBarTitleDisplayMode(.inline)
            .task(id: routine?.shareRecordID) {
                guard let id = routine?.shareRecordID else { remoteImageURL = nil; return }
                remoteImageURL = try? await RoutineShareService.shared.fetch(id: id).imageURL
            }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(t("add_entry.done")) { dismiss() } } }
            .onChange(of: selectedPhoto) { _, item in
                guard let item else { return }
                Task {
                    isLoadingPhoto = true
                    defer { isLoadingPhoto = false }
                    guard let data = try? await item.loadTransferable(type: Data.self),
                          let jpeg = await MainActor.run(body: { UIImage(data: data)?.hyseCompressedJPEG(maxDimension: 1400, maxBytes: 1_800_000) }),
                          let filename = try? RecipeImageStore.save(jpeg), var value = routine else {
                        errorMessage = t("training.routine.photo_failed")
                        return
                    }
                    value.imageFileName = filename
                    value.imageData = UIImage(data: jpeg)?.hyseCompressedJPEG(maxDimension: 700, maxBytes: 250_000) ?? jpeg
                    _ = store.saveRoutine(value)
                }
            }
            .sheet(item: $destination) { RoutineShareActivitySheet(url: $0.url) }
            .sheet(isPresented: $showingLogin) { LoginView().environmentObject(auth) }
            .alert(t("training.routine.share"), isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button(t("add_entry.done")) { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
            .onChange(of: auth.isLoggedIn) { _, loggedIn in
                if loggedIn && pendingShareAfterLogin {
                    pendingShareAfterLogin = false
                    showingLogin = false
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(350))
                        if let routine { await publish(routine) }
                    }
                }
            }
        }
    }

    private func publish(_ routine: WorkoutRoutine) async {
        guard !isPublishing else { return }
        isPublishing = true
        defer { isPublishing = false }
        await auth.refreshSession(force: true)
        guard auth.isLoggedIn, !auth.token.isEmpty else {
            pendingShareAfterLogin = true
            showingLogin = true
            return
        }
        let accountID = auth.accountID
        do {
            let id = try await RoutineShareService.shared.publish(routine: routine, ownerID: accountID, token: auth.token)
            guard auth.accountID == accountID, var updated = store.routines.first(where: { $0.id == routine.id }) else { return }
            updated.shareRecordID = id
            _ = store.saveRoutine(updated)
            if let url = RoutineShareLink.url(id: id, isGerman: language.isGerman) { destination = RoutineShareDestination(url: url) }
        } catch RoutineShareError.server(let status) {
            errorMessage = "\(t("training.routine.share_failed")) (HTTP \(status))"
        } catch RoutineShareError.tooLarge {
            errorMessage = t("training.routine.share_too_large")
        } catch { errorMessage = t("training.routine.share_failed") }
    }

    private func revoke(_ routine: WorkoutRoutine) async {
        guard let id = routine.shareRecordID, auth.isLoggedIn else { return }
        isPublishing = true
        defer { isPublishing = false }
        do {
            try await RoutineShareService.shared.revoke(id: id, token: auth.token)
            if var updated = store.routines.first(where: { $0.id == routine.id }) {
                updated.shareRecordID = nil
                _ = store.saveRoutine(updated)
            }
        } catch { errorMessage = t("training.routine.revoke_failed") }
    }

    private func removePhoto(_ routine: WorkoutRoutine) async {
        guard !isPublishing else { return }
        isPublishing = true
        defer { isPublishing = false }
        if let id = routine.shareRecordID {
            await auth.refreshSession(force: true)
            guard auth.isLoggedIn else { errorMessage = t("training.routine.photo_failed"); return }
            do { try await RoutineShareService.shared.removeImage(id: id, token: auth.token) }
            catch { errorMessage = t("training.routine.photo_failed"); return }
        }
        guard var updated = store.routines.first(where: { $0.id == routine.id }) else { return }
        updated.imageFileName = nil
        updated.imageData = nil
        remoteImageURL = nil
        _ = store.saveRoutine(updated)
    }
}

struct SharedRoutineDetailView: View {
    @EnvironmentObject private var language: LanguageStore
    @EnvironmentObject private var store: TrainingStore
    @EnvironmentObject private var premium: PremiumAccessStore
    let routine: SharedRoutine
    @State private var copied = false
    @State private var isCopying = false
    @State private var showingPremium = false
    @State private var copyError: String?

    private func t(_ key: String) -> String { language.text(key) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HyseSpacing.large) {
                if let url = routine.imageURL {
                    RoutinePhotoView(localData: nil, remoteURL: url, height: 240)
                }
                Text(routine.snapshot.name).font(.largeTitle.bold())
                    .fixedSize(horizontal: false, vertical: true)
                if !routine.snapshot.details.isEmpty { Text(routine.snapshot.details).foregroundStyle(.secondary) }
                Text(language.text("training.routine.exercise_count", [routine.snapshot.exercises.count]))
                    .font(.subheadline).foregroundStyle(.secondary)
                ForEach(Array(routine.snapshot.exercises.enumerated()), id: \.offset) { index, exercise in
                    HyseCard {
                        VStack(alignment: .leading, spacing: HyseSpacing.small) {
                            Text("\(index + 1). \(language.isGerman && !exercise.germanName.isEmpty ? exercise.germanName : (exercise.englishName.isEmpty ? exercise.germanName : exercise.englishName))")
                                .font(.headline)
                            Text(language.text("training.routine.share_set_count", [exercise.sets.count]))
                                .font(.subheadline).foregroundStyle(.secondary)
                            if !exercise.notes.isEmpty { Text(exercise.notes).font(.subheadline) }
                            ForEach(Array(exercise.sets.enumerated()), id: \.offset) { setIndex, set in
                                HStack(alignment: .firstTextBaseline) {
                                    Text("\(setIndex + 1).")
                                        .foregroundStyle(.secondary)
                                    Text(setDescription(set, type: exercise.type))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .font(.subheadline)
                            }
                        }
                    }
                }
            }
            .padding(HyseSpacing.page)
        }
        .background(HyseBackdrop())
        .navigationTitle(routine.snapshot.name)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button { Task { await copyRoutine() } } label: {
                if isCopying { ProgressView().frame(maxWidth: .infinity) }
                else { Label(t(copied ? "training.routine.copied" : "training.routine.copy_to_mine"), systemImage: copied ? "checkmark" : "square.on.square") }
            }
            .buttonStyle(HysePrimaryButtonStyle())
            .disabled(copied || isCopying)
            .padding(HyseSpacing.page)
            .background(HyseColor.background)
        }
        .sheet(isPresented: $showingPremium) { PremiumPaywallView(requestedArea: .training) }
        .alert(t("training.routine.share"), isPresented: Binding(get: { copyError != nil }, set: { if !$0 { copyError = nil } })) {
            Button(t("add_entry.done")) { copyError = nil }
        } message: { Text(copyError ?? "") }
    }

    private func copyRoutine() async {
        guard !isCopying, !copied else { return }
        isCopying = true
        defer { isCopying = false }
        var value = routine.snapshot.makeRoutine(catalog: store.exercises)
        guard !value.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !value.exercises.isEmpty else {
            copyError = t("training.routine.copy_failed")
            return
        }
        if let url = routine.imageURL {
            guard let (data, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let jpeg = UIImage(data: data)?.hyseCompressedJPEG(maxDimension: 1400, maxBytes: 1_800_000),
                  let filename = try? RecipeImageStore.save(jpeg) else {
                copyError = t("training.routine.photo_failed")
                return
            }
            value.imageFileName = filename
            value.imageData = UIImage(data: jpeg)?.hyseCompressedJPEG(maxDimension: 700, maxBytes: 250_000) ?? jpeg
        }
        if store.saveRoutine(value) { copied = true }
        else { showingPremium = true }
    }

    private func setDescription(_ set: SharedRoutineSnapshot.SetPlan, type: TrainingExerciseType) -> String {
        var parts: [String] = []
        if set.type != .normal { parts.append(language.text(set.type.localizationKey)) }
        switch type {
        case .duration, .distanceDuration:
            if set.distanceMeters > 0 { parts.append("\((set.distanceMeters / 1_000).formatted(.number.precision(.fractionLength(0...1)).grouping(.never))) km") }
            if set.durationSeconds > 0 { parts.append("\(Int(set.durationSeconds)) s") }
        case .weightReps, .bodyweight, .repsOnly:
            if set.weightKilograms > 0 { parts.append("\(set.weightKilograms.formatted(.number.precision(.fractionLength(0...1)).grouping(.never))) kg") }
            if set.assistedKilograms > 0 { parts.append("\(set.assistedKilograms.formatted(.number.precision(.fractionLength(0...1)).grouping(.never))) kg \(language.isGerman ? "Unterstützung" : "assistance")") }
            if set.reps > 0 { parts.append("\(set.reps) \(language.isGerman ? "Wdh." : "reps")") }
        }
        if let rpe = set.rpe, rpe > 0 { parts.append("RPE \(rpe.formatted(.number.precision(.fractionLength(0...1)).grouping(.never)))") }
        return parts.isEmpty ? (language.isGerman ? "Offener Satz" : "Open set") : parts.joined(separator: " · ")
    }
}
