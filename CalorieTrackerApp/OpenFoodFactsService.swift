import Foundation

nonisolated enum ExternalFoodLookupError: LocalizedError {
    case offline, rateLimited, server, invalidResponse
    var errorDescription: String? {
        switch self {
        case .offline: return LanguageStore.localizedString("barcode.external_offline")
        case .rateLimited: return LanguageStore.localizedString("barcode.external_rate_limited")
        case .server: return LanguageStore.localizedString("barcode.external_server_error")
        case .invalidResponse: return LanguageStore.localizedString("barcode.external_invalid_response")
        }
    }
}

/// Open Food Facts is CC BY-SA/ODbL data. Hyse displays the provider for an
/// imported private record and never sends account identifiers to this API.
actor OpenFoodFactsService {
    static let shared = OpenFoodFactsService()
    private static let contactEmail = HyseConfiguration.contactEmail
    private static var userAgent: String {
        let version = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "Hyse/\((version?.isEmpty == false ? version : nil) ?? "1.0") (\(contactEmail))"
    }
    private var inFlight: [String: Task<FoodItem?, Error>] = [:]
    private var positiveCache: [String: FoodItem] = [:]
    private var negativeCache: [String: Date] = [:]
    private let negativeTTL: TimeInterval = 5 * 60

    private struct OFFResponse: Decodable { let status: Int?; let product: OFFProduct? }
    private struct OFFProduct: Decodable {
        let productName: String?; let brands: String?; let nutriments: OFFNutriments?
        enum CodingKeys: String, CodingKey { case productName = "product_name"; case brands, nutriments }
    }
    private struct OFFNutriments: Decodable {
        let energyKcal100g: Double?; let energy100g: Double?; let carbs100g: Double?; let protein100g: Double?
        let fat100g: Double?; let sugar100g: Double?; let fiber100g: Double?; let saturatedFat100g: Double?; let salt100g: Double?
        let micronutrients: MicronutrientProfile?
        enum CodingKeys: String, CodingKey {
            case energyKcal100g = "energy-kcal_100g"; case energy100g = "energy_100g"
            case carbs100g = "carbohydrates_100g"; case protein100g = "proteins_100g"; case fat100g = "fat_100g"
            case sugar100g = "sugars_100g"; case fiber100g = "fiber_100g"; case saturatedFat100g = "saturated-fat_100g"; case salt100g = "salt_100g"
        }

        private struct NutrientKey: CodingKey {
            let stringValue: String
            let intValue: Int? = nil
            init(stringValue: String) { self.stringValue = stringValue }
            init?(intValue: Int) { return nil }
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            energyKcal100g = try c.decodeIfPresent(Double.self, forKey: .energyKcal100g)
            energy100g = try c.decodeIfPresent(Double.self, forKey: .energy100g)
            carbs100g = try c.decodeIfPresent(Double.self, forKey: .carbs100g)
            protein100g = try c.decodeIfPresent(Double.self, forKey: .protein100g)
            fat100g = try c.decodeIfPresent(Double.self, forKey: .fat100g)
            sugar100g = try c.decodeIfPresent(Double.self, forKey: .sugar100g)
            fiber100g = try c.decodeIfPresent(Double.self, forKey: .fiber100g)
            saturatedFat100g = try c.decodeIfPresent(Double.self, forKey: .saturatedFat100g)
            salt100g = try c.decodeIfPresent(Double.self, forKey: .salt100g)
            let raw = try decoder.container(keyedBy: NutrientKey.self)
            var values: [String: Double] = [:]
            for nutrient in Micronutrient.allCases {
                let key = NutrientKey(stringValue: "\(nutrient.openFoodFactsKey)_100g")
                if let grams = try? raw.decodeIfPresent(Double.self, forKey: key), grams.isFinite, grams >= 0 {
                    values[nutrient.rawValue] = grams * nutrient.gramsToDisplayUnit
                }
            }
            let profile = MicronutrientProfile(valuesPer100g: values, source: .database, sourceName: "Open Food Facts")
            micronutrients = profile.isEmpty ? nil : profile
        }
    }

    func fetchProduct(barcode rawBarcode: String) async throws -> FoodItem? {
        let barcode = try BarcodeNormalizer.normalize(rawBarcode)
        if let cached = positiveCache[barcode],
           let fetchedAt = cached.externalFetchedAt,
           Date().timeIntervalSince(fetchedAt) < 60 * 60 { return cached }
        positiveCache[barcode] = nil
        if let until = negativeCache[barcode], until > Date() { return nil }
        if let existing = inFlight[barcode] { return try await existing.value }
        let task = Task<FoodItem?, Error> { try await Self.request(barcode: barcode) }
        inFlight[barcode] = task
        do {
            let value = try await task.value
            inFlight[barcode] = nil
            if let value {
                positiveCache[barcode] = value
                if positiveCache.count > 200, let oldestKey = positiveCache.keys.first { positiveCache.removeValue(forKey: oldestKey) }
            } else {
                negativeCache[barcode] = Date().addingTimeInterval(negativeTTL)
            }
            return value
        } catch {
            inFlight[barcode] = nil
            throw error
        }
    }

    private static func request(barcode: String) async throws -> FoodItem? {
        guard var components = URLComponents(string: "https://world.openfoodfacts.org/api/v2/product/\(barcode).json") else {
            throw ExternalFoodLookupError.invalidResponse
        }
        components.queryItems = [URLQueryItem(name: "fields", value: "product_name,brands,nutriments")]
        guard let url = components.url else { throw ExternalFoodLookupError.invalidResponse }
        var request = URLRequest(url: url)
        // The same endpoint also refreshes existing foods in the background.
        // Keep an unavailable external service from blocking food creation.
        request.timeoutInterval = 2.0
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw ExternalFoodLookupError.invalidResponse }
            if http.statusCode == 429 { throw ExternalFoodLookupError.rateLimited }
            guard http.statusCode == 200 else { throw ExternalFoodLookupError.server }
            let decoded = try JSONDecoder().decode(OFFResponse.self, from: data)
            guard decoded.status == 1, let product = decoded.product else { return nil }
            // Some OFF records contain nutriments but no product name. Keep
            // their measured values usable for an already named Hyse food.
            let label = product.productName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !label.isEmpty || product.nutriments?.micronutrients != nil else { return nil }
            let name = label.isEmpty ? barcode : label
            var kcal = product.nutriments?.energyKcal100g ?? 0
            if kcal == 0, let kilojoules = product.nutriments?.energy100g { kcal = kilojoules / 4.184 }
            return FoodItem(
                name: name, brand: product.brands?.trimmingCharacters(in: .whitespacesAndNewlines),
                kcalPer100g: kcal.rounded(toPlaces: 1), carbsPer100g: (product.nutriments?.carbs100g ?? 0).rounded(toPlaces: 1),
                proteinPer100g: (product.nutriments?.protein100g ?? 0).rounded(toPlaces: 1), fatPer100g: (product.nutriments?.fat100g ?? 0).rounded(toPlaces: 1),
                sugarPer100g: (product.nutriments?.sugar100g ?? 0).rounded(toPlaces: 1), fiberPer100g: (product.nutriments?.fiber100g ?? 0).rounded(toPlaces: 1),
                saturatedFatPer100g: (product.nutriments?.saturatedFat100g ?? 0).rounded(toPlaces: 1), saltPer100g: (product.nutriments?.salt100g ?? 0).rounded(toPlaces: 1),
                micronutrients: product.nutriments?.micronutrients,
                barcode: barcode, externalSource: "Open Food Facts", externalSourceID: barcode, externalFetchedAt: Date()
            )
        } catch let error as ExternalFoodLookupError { throw error }
        catch let error as URLError where [.notConnectedToInternet, .networkConnectionLost, .timedOut].contains(error.code) { throw ExternalFoodLookupError.offline }
        catch is DecodingError { throw ExternalFoodLookupError.invalidResponse }
        catch { throw ExternalFoodLookupError.server }
    }
}
