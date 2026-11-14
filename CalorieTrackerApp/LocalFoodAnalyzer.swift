import Foundation

nonisolated struct LocalFoodAnalysisMatch: Identifiable, Sendable {
    let id: UUID
    let food: FoodItem
    let baseAmount: Double
    let confidence: Double
    let evidence: String

    init(food: FoodItem, baseAmount: Double, confidence: Double, evidence: String) {
        id = UUID()
        self.food = food
        self.baseAmount = baseAmount
        self.confidence = confidence
        self.evidence = evidence
    }
}

/// Fully on-device food recognition. Exact quantities are parsed
/// deterministically; Apple Intelligence is only used as a local fallback for
/// ambiguous natural language. Nutrients are never invented and always come
/// from the local FoodItem.
actor LocalFoodAnalyzer {
    static let shared = LocalFoodAnalyzer()

    func matchComponents(_ components: [LocalFoodTextComponent], foods: [FoodItem]) -> [LocalFoodAnalysisMatch] {
        Self.merged(Self.matches(for: components, foods: foods))
    }

    func analyzeText(_ text: String, foods: [FoodItem]) async -> [LocalFoodAnalysisMatch] {
        let components = LocalFoodTextParser.parse(text)
        let deterministic = Self.matches(for: components, foods: foods)
        let isReliable = deterministic.count == components.count
            && !deterministic.isEmpty
            && deterministic.allSatisfy { $0.confidence >= 0.70 }
        let hasExplicitQuantities = !components.isEmpty
            && components.allSatisfy { $0.quantity != nil && $0.unit != nil }
        if isReliable || hasExplicitQuantities { return Self.merged(deterministic) }

#if canImport(FoundationModels)
        if #available(iOS 26.0, *),
           let modelComponents = await AppleFoodLanguageParser.parse(text) {
            let modelMatches = Self.matches(for: modelComponents, foods: foods)
            if Self.quality(of: modelMatches) > Self.quality(of: deterministic) {
                return Self.merged(modelMatches)
            }
        }
#endif
        return Self.merged(deterministic)
    }

    private static func matches(for components: [LocalFoodTextComponent], foods: [FoodItem]) -> [LocalFoodAnalysisMatch] {
        components.compactMap { component in
            let terms = expandedTerms(for: component.foodQuery)
            guard let originalTerm = terms.first else { return nil }
            // The user's own food name takes precedence over translations and
            // aliases. An alias such as "tomato" must not turn "Tomate" into
            // a tomato sauce or spread when a plain tomato is available.
            let result = bestFoodMatch(for: originalTerm, foods: foods, minimumScore: 0.52)
                ?? terms.dropFirst().compactMap {
                    bestFoodMatch(for: $0, foods: foods, minimumScore: 0.52)
                }.max(by: { $0.score < $1.score })
            guard let result else { return nil }
            return LocalFoodAnalysisMatch(
                food: result.food,
                baseAmount: amount(for: component, food: result.food),
                confidence: result.score,
                evidence: component.rawText
            )
        }
    }

    private static func amount(for component: LocalFoodTextComponent, food: FoodItem) -> Double {
        guard let quantity = component.quantity, let unit = component.unit else {
            return food.defaultPortionBaseAmount ?? 100
        }
        switch unit {
        case .gram:
            return FoodUnit.gram.converted(quantity, to: food.unit) ?? quantity
        case .kilogram:
            return FoodUnit.gram.converted(quantity * 1_000, to: food.unit) ?? quantity * 1_000
        case .milliliter:
            return FoodUnit.milliliter.converted(quantity, to: food.unit) ?? quantity
        case .liter:
            return FoodUnit.milliliter.converted(quantity * 1_000, to: food.unit) ?? quantity * 1_000
        case .ounce:
            return FoodUnit.ounce.converted(quantity, to: food.unit) ?? quantity * 28.349_523_125
        case .fluidOunce:
            return FoodUnit.fluidOunce.converted(quantity, to: food.unit) ?? quantity * 29.573_529_562_5
        case .portion:
            return max((food.defaultPortionBaseAmount ?? 100) * quantity, 1)
        case .slice:
            return max((namedPortionAmount(for: .slice, food: food) ?? sliceAmount(for: food)) * quantity, 1)
        case .piece, .count:
            return max((namedPortionAmount(for: .piece, food: food) ?? pieceAmount(for: food)) * quantity, 1)
        case .plate:
            return max((namedPortionAmount(for: .plate, food: food) ?? food.defaultPortionBaseAmount ?? 250) * quantity, 1)
        case .bowl:
            return max((namedPortionAmount(for: .bowl, food: food) ?? food.defaultPortionBaseAmount ?? 300) * quantity, 1)
        case .cup:
            return max((namedPortionAmount(for: .cup, food: food) ?? food.defaultPortionBaseAmount ?? householdAmount(milliliters: 236.588, massFallback: 200, food: food)) * quantity, 1)
        case .tablespoon:
            return max((namedPortionAmount(for: .tablespoon, food: food) ?? householdAmount(milliliters: 14.787, massFallback: 15, food: food)) * quantity, 1)
        case .teaspoon:
            return max((namedPortionAmount(for: .teaspoon, food: food) ?? householdAmount(milliliters: 4.929, massFallback: 5, food: food)) * quantity, 1)
        }
    }

    private static func namedPortionAmount(for unit: LocalFoodTextUnit, food: FoodItem) -> Double? {
        let terms: [String]
        switch unit {
        case .slice: terms = ["scheibe", "slice"]
        case .piece, .count: terms = ["stuck", "stueck", "piece", "serving"]
        case .plate: terms = ["teller", "plate"]
        case .bowl: terms = ["schussel", "schuessel", "bowl"]
        case .cup: terms = ["tasse", "cup"]
        case .tablespoon: terms = ["essloffel", "essloeffel", "tablespoon", "tbsp", "tbs"]
        case .teaspoon: terms = ["teeloffel", "teeloeffel", "teaspoon", "tsp"]
        default: return nil
        }
        return food.portions.first(where: { portion in
            let name = normalized("\(portion.nameKey ?? "") \(portion.customName)")
            return terms.contains(where: name.contains)
        })?.baseAmount(in: food.unit)
    }

    private static func householdAmount(milliliters: Double, massFallback: Double, food: FoodItem) -> Double {
        FoodUnit.milliliter.converted(milliliters, to: food.unit) ?? massFallback
    }

    private static func pieceAmount(for food: FoodItem) -> Double {
        if let portion = food.defaultPortionBaseAmount { return portion }
        let value = normalized("\(food.name) \(food.nameDE ?? "")")
        let values: [(terms: [String], amount: Double)] = [
            (["ei", "eier", "egg"], 60), (["apfel", "apple"], 180), (["banane", "banana"], 120),
            (["orange"], 160), (["avocado"], 150), (["kartoffel", "potato"], 180),
            (["burger", "hamburger"], 220), (["pizza"], 350), (["kuchen", "cake"], 120)
        ]
        return values.first(where: { pair in pair.terms.contains(where: value.contains) })?.amount ?? 100
    }

    private static func sliceAmount(for food: FoodItem) -> Double {
        let value = normalized("\(food.name) \(food.nameDE ?? "")")
        let values: [(terms: [String], amount: Double)] = [
            (["brot", "toast", "bread"], 45), (["kase", "cheese"], 25),
            (["schinken", "ham"], 25), (["apfel", "apple"], 25), (["banane", "banana"], 20)
        ]
        return values.first(where: { pair in pair.terms.contains(where: value.contains) })?.amount ?? 30
    }

    private static let aliasGroups: [[String]] = [
        ["apple", "apfel", "granny smith", "red delicious", "golden delicious"],
        ["pineapple", "ananas"], ["banana", "banane"], ["orange"],
        ["strawberry", "erdbeere"], ["grape", "weintraube", "traube"],
        ["bread", "brot", "vollkornbrot"], ["toast", "toastbrot"], ["rice", "reis"],
        ["pasta", "noodle", "nudeln"], ["oatmeal", "oats", "porridge", "haferflocken"],
        ["protein powder", "proteinpulver", "whey protein", "whey"], ["egg", "eggs", "ei", "eier"],
        ["omelet", "omelette", "omelett"],
        ["chicken", "chicken breast", "hahnchen", "hahnchenbrust", "huhn", "huhnerbrust", "drumstick"],
        ["beef", "rind", "rindfleisch"], ["ground beef", "minced beef", "beef mince", "hackfleisch", "rinderhack"],
        ["steak", "filet mignon"], ["pork", "schwein", "schweinefleisch"],
        ["fish", "fisch"], ["salmon", "lachs", "grilled salmon"], ["tuna", "thunfisch"],
        ["broccoli", "brokkoli"], ["carrot", "karotte", "mohre"], ["potato", "kartoffel"],
        ["french fries", "pommes"], ["salad", "salat"], ["tomato", "tomate"],
        ["tomato sauce", "marinara", "tomatensosse", "tomatensauce"], ["bell pepper", "paprika"],
        ["cucumber", "gurke"], ["zucchini", "courgette"], ["avocado"],
        ["pizza"], ["hamburger", "burger"], ["soup", "suppe"], ["cheese", "kase"],
        ["yogurt", "yoghurt", "joghurt"], ["greek yogurt", "greek yoghurt", "griechischer joghurt"],
        ["cottage cheese", "huttenkase", "korniger frischkase"], ["milk", "milch"], ["butter"],
        ["peanut butter", "erdnussbutter"], ["olive oil", "olivenol"], ["cake", "kuchen"],
        ["cookie", "keks"], ["chocolate", "schokolade"], ["nuts", "nusse"],
        ["almond", "mandel"], ["peanut", "erdnuss"], ["ice cream", "eiscreme", "speiseeis"],
        ["pancakes", "pfannkuchen"], ["waffles", "waffeln"], ["sushi"], ["ramen"],
        ["lasagna", "lasagne"], ["spaghetti bolognese", "bolognese"],
        ["spaghetti carbonara", "carbonara"], ["fried rice", "gebratener reis"],
        ["tacos", "taco"], ["burrito"], ["dumplings", "teigtaschen"], ["hummus"], ["falafel"]
    ]

    private static func expandedTerms(for label: String) -> [String] {
        let value = normalized(label)
        guard !value.isEmpty else { return [] }
        var terms = [value]
        for group in aliasGroups where group.contains(where: { alias in
            let normalizedAlias = normalized(alias)
            return value == normalizedAlias || significantTokens(value) == significantTokens(normalizedAlias)
        }) {
            terms.append(contentsOf: group)
        }
        var seen = Set<String>()
        return terms.map(normalized).filter { seen.insert($0).inserted }
    }

    private static func bestFoodMatch(
        for phrase: String,
        foods: [FoodItem],
        minimumScore: Double
    ) -> (food: FoodItem, score: Double)? {
        let query = normalized(phrase)
        let queryTokens = significantTokens(query)
        guard !query.isEmpty, !queryTokens.isEmpty else { return nil }

        var best: (food: FoodItem, score: Double)?
        for food in foods {
            let names = [food.name, food.nameDE].compactMap { $0 }.map(normalized)
            var foodScore = names.map { score(query: query, queryTokens: queryTokens, candidate: $0) }.max() ?? 0
            if let brand = food.brand, !brand.isEmpty {
                foodScore = max(foodScore, score(query: query, queryTokens: queryTokens, candidate: normalized(brand)) * 0.68)
            }
            if foodScore >= minimumScore, foodScore > (best?.score ?? 0) {
                best = (food, foodScore)
            }
        }
        return best
    }

    private static func score(query: String, queryTokens: Set<String>, candidate: String) -> Double {
        guard !candidate.isEmpty else { return 0 }
        if query == candidate { return 1 }
        let candidateTokens = significantTokens(candidate)
        guard !candidateTokens.isEmpty else { return 0 }
        // For a one-word request, additional ingredients or product terms
        // change the food. Descriptors such as "raw" or "red" do not.
        if queryTokens.count == 1, candidateTokens.count > 1 {
            let queryToken = queryTokens.first!
            let matched = candidateTokens.filter { tokenSimilarity(queryToken, $0) >= 0.77 }
            let descriptors: Set<String> = [
                "roh", "raw", "frisch", "fresh", "rot", "red", "grun", "green", "gelb", "yellow",
                "reif", "ripe", "gekocht", "cooked", "gegart", "boiled", "gebraten", "fried",
                "gesalzen", "salted", "ungesalzen", "unsalted", "natur", "plain", "trocken", "dry",
                "geschaelt", "peeled", "schale", "skin", "mit", "ohne", "with", "without",
                "weiss", "white", "braun", "brown", "ganz", "whole", "fettarm", "low", "fat",
                "year", "round", "average", "lang", "long", "korn", "grain", "regular", "enriched"
            ]
            if matched.isEmpty || candidateTokens.contains(where: { !matched.contains($0) && !descriptors.contains($0) }) {
                return 0
            }
        }
        var candidateTotal = 0.0
        for token in candidateTokens {
            candidateTotal += queryTokens.map { tokenSimilarity($0, token) }.max() ?? 0
        }
        var queryTotal = 0.0
        for token in queryTokens {
            queryTotal += candidateTokens.map { tokenSimilarity(token, $0) }.max() ?? 0
        }
        let candidateCoverage = candidateTotal / Double(candidateTokens.count)
        let queryCoverage = queryTotal / Double(queryTokens.count)
        if queryCoverage < 0.70 { return 0 }
        let combined = 0.34 + candidateCoverage * 0.34 + queryCoverage * 0.27
        return max(candidateCoverage, queryCoverage) < 0.70 ? 0 : min(combined, 0.95)
    }

    private static func tokenSimilarity(_ lhs: String, _ rhs: String) -> Double {
        let left = canonicalToken(lhs)
        let right = canonicalToken(rhs)
        if left == right { return 1 }
        let shortest = min(left.count, right.count)
        if shortest >= 3, (left.hasPrefix(right) || right.hasPrefix(left)),
           abs(left.count - right.count) <= 3 { return 0.84 }
        guard shortest >= 4 else { return 0 }
        let distance = editDistance(left, right)
        if distance == 1 { return 0.90 }
        if distance == 2, shortest >= 6 { return 0.77 }
        return 0
    }

    private static func canonicalToken(_ value: String) -> String {
        switch value {
        case "eier", "eggs": "ei"
        case "apples": "apple"
        case "bananas": "banana"
        case "tomatoes": "tomato"
        default: value
        }
    }

    private static func significantTokens(_ value: String) -> Set<String> {
        let ignored: Set<String> = [
            "g", "gr", "gramm", "grams", "kg", "ml", "l", "oz", "fl", "portion", "portionen",
            "serving", "servings", "stuck", "stueck", "scheibe", "scheiben", "slice", "piece", "teller", "plate",
            "bowl", "cup", "tablespoon", "tbsp", "tbs", "teaspoon", "tsp", "x",
            "eine", "einen", "einer", "einem", "eines", "ein", "der", "die", "das", "ungefahr", "ca",
            "ich", "habe", "hatte", "zum", "zur", "fruhstuck", "mittagessen", "abendessen", "gegessen",
            "of", "the", "a", "an", "i", "had", "ate", "approximately", "about", "small", "medium", "large", "cooked", "grilled", "scrambled"
        ]
        return Set(value
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { !ignored.contains($0) && Double($0.replacingOccurrences(of: ",", with: ".")) == nil })
    }

    private static func editDistance(_ lhs: String, _ rhs: String) -> Int {
        let left = Array(lhs)
        let right = Array(rhs)
        var previous = Array(0...right.count)
        for (leftIndex, leftCharacter) in left.enumerated() {
            var current = [leftIndex + 1] + Array(repeating: 0, count: right.count)
            for (rightIndex, rightCharacter) in right.enumerated() {
                current[rightIndex + 1] = min(
                    current[rightIndex] + 1,
                    previous[rightIndex + 1] + 1,
                    previous[rightIndex] + (leftCharacter == rightCharacter ? 0 : 1)
                )
            }
            previous = current
        }
        return previous[right.count]
    }

    private static func wholePhrase(_ value: String, contains phrase: String) -> Bool {
        guard !phrase.isEmpty else { return false }
        return " \(value) ".contains(" \(phrase) ")
    }

    private static func normalized(_ value: String) -> String {
        let folded = value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "de_DE"))
            .lowercased()
            .replacingOccurrences(of: "ß", with: "ss")
        let expression = try! NSRegularExpression(pattern: "[^a-z0-9]+", options: [])
        let range = NSRange(folded.startIndex..., in: folded)
        return expression
            .stringByReplacingMatches(in: folded, range: range, withTemplate: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func quality(of values: [LocalFoodAnalysisMatch]) -> Double {
        guard !values.isEmpty else { return 0 }
        return Double(values.count) * 2 + values.reduce(0) { $0 + $1.confidence } / Double(values.count)
    }

    private static func merged(_ values: [LocalFoodAnalysisMatch]) -> [LocalFoodAnalysisMatch] {
        var ordered: [LocalFoodAnalysisMatch] = []
        for value in values {
            if let index = ordered.firstIndex(where: { $0.food.id == value.food.id }) {
                let previous = ordered[index]
                ordered[index] = LocalFoodAnalysisMatch(
                    food: value.food,
                    baseAmount: previous.baseAmount + value.baseAmount,
                    confidence: max(previous.confidence, value.confidence),
                    evidence: previous.evidence + ", " + value.evidence
                )
            } else {
                ordered.append(value)
            }
        }
        return ordered
    }
}
