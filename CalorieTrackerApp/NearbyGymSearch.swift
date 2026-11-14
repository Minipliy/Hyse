import Combine
import SwiftUI
import CoreLocation
import MapKit
import UIKit

struct NearbyGym: Identifiable, Hashable {
    let name: String
    let address: String
    let distance: CLLocationDistance
    let coordinate: CLLocationCoordinate2D

    var id: String {
        "\(name)|\(coordinate.latitude)|\(coordinate.longitude)"
    }

    static func == (lhs: NearbyGym, rhs: NearbyGym) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

private struct GymNameAlias {
    let canonicalName: String
    let street: String
    let postalCode: String
    let mapNames: [String]
}

@MainActor
final class NearbyGymSearchModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    enum Problem {
        case locationDenied
        case locationUnavailable
        case searchFailed
    }

    @Published private(set) var gyms: [NearbyGym] = []
    @Published private(set) var isLoading = false
    @Published private(set) var problem: Problem?

    private let locationManager = CLLocationManager()
    private var searchTask: Task<Void, Never>?
    private var pendingQuery = ""

    // Apple Maps occasionally lists a branch under a former or parent brand.
    // These aliases keep the result recognizable while retaining the map pin,
    // address and coordinates supplied by Maps.
    private static let gymNameAliases = [
        GymNameAlias(
            canonicalName: "FittiCO Dresden Mitte",
            street: "Berliner Straße 27",
            postalCode: "01067",
            mapNames: ["all inclusive FITNESS", "FittiCO"]
        )
    ]

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    deinit {
        searchTask?.cancel()
    }

    func findNearbyGyms(matching query: String = "") {
        searchTask?.cancel()
        pendingQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        problem = nil
        switch locationManager.authorizationStatus {
        case .notDetermined:
            isLoading = true
            locationManager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            isLoading = true
            locationManager.requestLocation()
        case .denied, .restricted:
            isLoading = false
            problem = .locationDenied
        @unknown default:
            isLoading = false
            problem = .locationUnavailable
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            isLoading = true
            manager.requestLocation()
        case .denied, .restricted:
            isLoading = false
            problem = .locationDenied
        case .notDetermined:
            break
        @unknown default:
            isLoading = false
            problem = .locationUnavailable
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            isLoading = false
            problem = .locationUnavailable
            return
        }
        search(around: location, matching: pendingQuery)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        isLoading = false
        problem = .locationUnavailable
    }

    private func search(around location: CLLocation, matching query: String) {
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            guard let self else { return }

            // Apple Maps does not consistently tag every studio as a fitness center.
            // Keep the category search, then broaden it with an unrestricted gym search.
            let plans: [(query: String, filter: MKPointOfInterestFilter?)] = query.isEmpty
                ? [
                    ("Fitnessstudio", MKPointOfInterestFilter(including: [.fitnessCenter])),
                    ("Gym", nil)
                ]
                : [
                    // A street/address by itself often resolves to a single
                    // map pin. Pair it with the two common fitness terms so
                    // branches on that street (for example FittiCo) remain
                    // discoverable even when Maps lacks a fitness category.
                    (query, nil),
                    ("Fitnessstudio \(query)", nil),
                    ("Gym \(query)", nil)
                ]
            let aliasPlans: [(query: String, filter: MKPointOfInterestFilter?)] = Self.gymNameAliases.flatMap { alias in
                alias.mapNames.map { name in
                    (query: query.isEmpty ? name : "\(name) \(query)", filter: nil)
                }
            }
            var mapItems: [MKMapItem] = []
            var didReceiveResponse = false

            for plan in plans + aliasPlans {
                let request = MKLocalSearch.Request()
                request.naturalLanguageQuery = plan.query
                request.resultTypes = .pointOfInterest
                request.pointOfInterestFilter = plan.filter
                request.region = MKCoordinateRegion(
                    center: location.coordinate,
                    latitudinalMeters: 20_000,
                    longitudinalMeters: 20_000
                )

                do {
                    let response = try await MKLocalSearch(request: request).start()
                    guard !Task.isCancelled else { return }
                    didReceiveResponse = true
                    mapItems.append(contentsOf: response.mapItems)
                } catch is CancellationError {
                    return
                } catch {
                    // A second query can still return results when one search fails.
                }
            }

            guard !Task.isCancelled else { return }
            gyms = mapItems.compactMap { item in
                guard let name = item.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
                    return nil
                }
                let coordinate = item.placemark.coordinate
                let destination = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                let address = Self.address(for: item.placemark)
                return NearbyGym(
                    name: Self.displayName(for: name, at: item.placemark),
                    address: address,
                    distance: location.distance(from: destination),
                    coordinate: coordinate
                )
            }
                .sorted { $0.distance < $1.distance }
                .uniqued(by: \NearbyGym.id)
                .prefix(50)
                .map { $0 }

            isLoading = false
            problem = didReceiveResponse ? nil : .searchFailed
        }
    }

    private static func address(for placemark: MKPlacemark) -> String {
        let street = [placemark.thoroughfare, placemark.subThoroughfare]
            .compactMap { $0 }
            .joined(separator: " ")
        let city = [placemark.postalCode, placemark.locality]
            .compactMap { $0 }
            .joined(separator: " ")
        let region = city.isEmpty ? (placemark.administrativeArea ?? "") : ""
        return [street, city, region, placemark.country ?? ""]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    private static func displayName(for mapName: String, at placemark: MKPlacemark) -> String {
        guard let alias = gymNameAliases.first(where: { alias in
            let mapNameMatches = alias.mapNames.contains {
                normalized(mapName).contains(normalized($0))
            }
            let street = [placemark.thoroughfare, placemark.subThoroughfare]
                .compactMap { $0 }
                .joined(separator: " ")
            return mapNameMatches
                && normalized(street) == normalized(alias.street)
                && placemark.postalCode == alias.postalCode
        }) else {
            return mapName
        }
        return alias.canonicalName
    }

    private static func normalized(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: "ß", with: "ss")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
    }
}

private extension Sequence {
    func uniqued<Key: Hashable>(by keyPath: KeyPath<Element, Key>) -> [Element] {
        var seen = Set<Key>()
        return filter { seen.insert($0[keyPath: keyPath]).inserted }
    }
}

struct NearbyGymPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var language: LanguageStore
    @StateObject private var model = NearbyGymSearchModel()
    @State private var gymQuery = ""

    let selectedGymID: String?
    let onSelect: (NearbyGym) -> Void

    private func t(_ key: String, _ arguments: CVarArg...) -> String {
        language.text(key, arguments)
    }

    var body: some View {
        ZStack {
            HyseBackdrop()
            VStack(spacing: 0) {
                searchField
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(t("training.completion.nearby_gyms.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(t("app_tabs.cancel")) { dismiss() }
            }
            ToolbarItem(placement: .primaryAction) {
                Button { model.findNearbyGyms(matching: gymQuery) } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(model.isLoading)
                .accessibilityLabel(t("training.completion.nearby_gyms.refresh"))
            }
        }
        .task {
            if model.gyms.isEmpty && model.problem == nil {
                model.findNearbyGyms(matching: gymQuery)
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: HyseSpacing.small) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(t("training.completion.nearby_gyms.search_placeholder"), text: $gymQuery)
                .textInputAutocapitalization(.words)
                .submitLabel(.search)
                .onSubmit { model.findNearbyGyms(matching: gymQuery) }
            Button { model.findNearbyGyms(matching: gymQuery) } label: {
                Image(systemName: "arrow.right.circle.fill")
                    .foregroundStyle(HyseColor.accent)
            }
            .disabled(model.isLoading)
            .accessibilityLabel(t("training.completion.nearby_gyms.search"))
        }
        .padding(HyseSpacing.medium)
        .background(HyseColor.elevatedSurface, in: RoundedRectangle(cornerRadius: HyseRadius.card, style: .continuous))
        .padding(.horizontal, HyseSpacing.page)
        .padding(.top, HyseSpacing.small)
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading && model.gyms.isEmpty {
            VStack(spacing: HyseSpacing.medium) {
                ProgressView()
                    .controlSize(.large)
                    .tint(HyseColor.accent)
                Text(t("training.completion.nearby_gyms.searching"))
                    .foregroundStyle(.secondary)
            }
        } else if let problem = model.problem, model.gyms.isEmpty {
            problemView(problem)
        } else if model.gyms.isEmpty {
            problemView(.searchFailed)
        } else {
            ScrollView {
                LazyVStack(spacing: HyseSpacing.small) {
                    HStack(spacing: HyseSpacing.small) {
                        Image(systemName: "location.fill")
                            .foregroundStyle(HyseColor.accent)
                        Text(t("training.completion.nearby_gyms.live_results"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.bottom, HyseSpacing.small)

                    ForEach(model.gyms) { gym in
                        Button {
                            onSelect(gym)
                            dismiss()
                        } label: {
                            HStack(spacing: HyseSpacing.medium) {
                                Image(systemName: "dumbbell.fill")
                                    .font(.title3)
                                    .foregroundStyle(HyseColor.accent)
                                    .frame(width: 42, height: 42)
                                    .background(HyseColor.accent.opacity(0.14), in: Circle())

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(gym.name)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                        .multilineTextAlignment(.leading)
                                    if !gym.address.isEmpty {
                                        Text(gym.address)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                }

                                Spacer(minLength: HyseSpacing.small)

                                VStack(alignment: .trailing, spacing: 5) {
                                    Text(distanceText(gym.distance))
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    if selectedGymID == gym.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(HyseColor.success)
                                    } else {
                                        Image(systemName: "chevron.right")
                                            .font(.caption.bold())
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            }
                            .padding(HyseSpacing.medium)
                            .background(HyseColor.elevatedSurface, in: RoundedRectangle(cornerRadius: HyseRadius.card, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: HyseRadius.card, style: .continuous)
                                    .stroke(selectedGymID == gym.id ? HyseColor.accent.opacity(0.8) : HyseColor.border)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(HyseSpacing.page)
            }
            .refreshable { model.findNearbyGyms(matching: gymQuery) }
        }
    }

    private func problemView(_ problem: NearbyGymSearchModel.Problem) -> some View {
        VStack(spacing: HyseSpacing.medium) {
            Image(systemName: problem == .locationDenied ? "location.slash.fill" : "mappin.slash.circle.fill")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(HyseColor.accent)
            Text(t(problem == .locationDenied
                   ? "training.completion.nearby_gyms.permission_title"
                   : "training.completion.nearby_gyms.error_title"))
                .font(.title3.bold())
            Text(t(problem == .locationDenied
                   ? "training.completion.nearby_gyms.permission_message"
                   : "training.completion.nearby_gyms.error_message"))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button {
                if problem == .locationDenied {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                } else {
                    model.findNearbyGyms(matching: gymQuery)
                }
            } label: {
                Text(t(problem == .locationDenied
                       ? "training.completion.nearby_gyms.open_settings"
                       : "training.completion.nearby_gyms.retry"))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, HyseSpacing.medium)
            }
            .buttonStyle(.borderedProminent)
            .tint(HyseColor.accent)
            .padding(.top, HyseSpacing.small)
        }
        .padding(HyseSpacing.xLarge)
    }

    private func distanceText(_ distance: CLLocationDistance) -> String {
        if distance < 1_000 {
            return "\(Int(distance.rounded())) m"
        }
        return "\((distance / 1_000).formatted(.number.precision(.fractionLength(1)).locale(language.locale))) km"
    }
}
