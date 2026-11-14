import SwiftUI

nonisolated struct GymChallengeStatus: Decodable, Sendable {
    let week: String
    let goal: Int
    let joined: Bool
    let participants: Int
    let completed: Int
    let myCount: Int
    enum CodingKeys: String, CodingKey {
        case week, goal, joined, participants, completed
        case myCount = "my_count"
    }
}

actor GymChallengeService {
    static let shared = GymChallengeService()
    private let baseURL = HyseConfiguration.serverURL

    func status(communityID: String, token: String) async throws -> GymChallengeStatus {
        try await request(communityID: communityID, token: token, enabled: nil)
    }

    func setJoined(_ joined: Bool, communityID: String, token: String) async throws -> GymChallengeStatus {
        try await request(communityID: communityID, token: token, enabled: joined)
    }

    private func request(communityID: String, token: String, enabled: Bool?) async throws -> GymChallengeStatus {
        guard let url = URL(string: "\(baseURL)/api/hyse/gym-communities/\(communityID)/challenge") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 25
        request.httpMethod = enabled == nil ? "GET" : "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let enabled {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(["enabled": enabled])
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, (200...299).contains(response.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(GymChallengeStatus.self, from: data)
    }
}

struct GymCommunityChallengeView: View {
    @EnvironmentObject private var language: LanguageStore
    @EnvironmentObject private var auth: AuthManager
    @Environment(\.dismiss) private var dismiss
    let community: GymCommunity
    @State private var status: GymChallengeStatus?
    @State private var isWorking = false
    @State private var failed = false
    private func t(_ key: String, _ arguments: CVarArg...) -> String { language.text(key, arguments) }

    var body: some View {
        NavigationStack {
            ZStack {
                HyseBackdrop()
                ScrollView {
                    VStack(alignment: .leading, spacing: HyseSpacing.large) {
                        HyseCard(accent: HyseColor.accent) {
                            VStack(alignment: .leading, spacing: HyseSpacing.medium) {
                                Label(t("challenge.title"), systemImage: "figure.strengthtraining.traditional")
                                    .font(.title2.bold())
                                Text(t("challenge.description", 3))
                                    .font(.subheadline)
                                Text(t("challenge.week_utc"))
                                    .font(.caption).foregroundStyle(.secondary)
                                Text(t("challenge.sync_note"))
                                    .font(.caption).foregroundStyle(.secondary)
                                if let status {
                                    ProgressView(value: Double(min(status.myCount, status.goal)), total: Double(status.goal))
                                        .tint(HyseColor.accent)
                                    Text(t("challenge.my_progress", status.myCount, status.goal))
                                        .font(.headline)
                                    Text(t("challenge.community_progress", status.completed, status.participants))
                                        .font(.subheadline).foregroundStyle(.secondary)
                                    Button(t(status.joined ? "challenge.leave" : "challenge.join")) {
                                        Task { await setJoined(!status.joined) }
                                    }
                                    .buttonStyle(HysePrimaryButtonStyle())
                                    .disabled(isWorking)
                                } else if isWorking {
                                    ProgressView()
                                }
                            }
                        }
                        if failed {
                            HyseStatusBanner(title: t("challenge.error_title"), message: t("challenge.error"), style: .warning,
                                             actionTitle: t("content.retry"), action: { Task { await load() } })
                        }
                    }
                    .padding(HyseSpacing.page)
                }
            }
            .navigationTitle(community.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(t("add_entry.done")) { dismiss() } } }
            .task { await load() }
        }
    }

    private func load() async {
        guard !auth.token.isEmpty else { failed = true; return }
        isWorking = true
        defer { isWorking = false }
        do {
            status = try await GymChallengeService.shared.status(communityID: community.id, token: auth.token)
            failed = false
        } catch { failed = true }
    }

    private func setJoined(_ joined: Bool) async {
        isWorking = true
        defer { isWorking = false }
        do {
            status = try await GymChallengeService.shared.setJoined(joined, communityID: community.id, token: auth.token)
            failed = false
        } catch { failed = true }
    }
}
