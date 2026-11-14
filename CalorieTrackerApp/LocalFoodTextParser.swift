import Foundation

/// Units understood by the local meal text parser. These are intentionally
/// independent of `FoodUnit`: portion-like units need a food before Hyse can
/// turn them into a canonical amount.
nonisolated enum LocalFoodTextUnit: String, Sendable, Equatable {
    case gram
    case kilogram
    case milliliter
    case liter
    case ounce
    case fluidOunce
    case portion
    case slice
    case piece
    case plate
    case bowl
    case cup
    case tablespoon
    case teaspoon
    case count
}

nonisolated struct LocalFoodTextComponent: Sendable, Equatable {
    let rawText: String
    let foodQuery: String
    let quantity: Double?
    let unit: LocalFoodTextUnit?
}

/// A deterministic parser for common and unusual food-entry formats. It runs
/// before any language model so exact quantities such as `45g` can never be
/// reinterpreted as 45 portions.
nonisolated enum LocalFoodTextParser {
    private struct QuantityMatch {
        let quantity: Double
        let unit: LocalFoodTextUnit
        let range: NSRange
    }

    private static let explicitQuantity = try! NSRegularExpression(
        pattern: #"(?<![\p{L}\p{N}])(\d+(?:[\.,]\d+)?)\s*(fl\.?\s*oz\.?|fluid\s*ounces?|fluid\s*ounce|flüssig(?:e|en)?\s*unzen?|kilogramm|kilograms?|kilos?|kg|milliliters?|millilitre|milliliter|ml|liters?|litres?|liter|l|gramm|grams?|grammes?|gr\.?|g|ounces?|unzen?|oz|tablespoons?|tbsp\.?|tbs\.?|teaspoons?|tsp\.?|cups?|bowls?|portion(?:en|s)?|servings?|scheibe(?:n)?|slices?|stück(?:e)?|stueck(?:e)?|pieces?|teller|plates?|x)(?![\p{L}])"#,
        options: [.caseInsensitive]
    )

    private static let leadingWordQuantity = try! NSRegularExpression(
        pattern: #"^\s*(?:(?:approximately|about)\s*)?(a|an|one|two|three|four|five|six)\s+(tablespoons?|tbsp\.?|tbs\.?|teaspoons?|tsp\.?|cups?|bowls?|servings?|portions?|slices?|pieces?|plates?)\b"#,
        options: [.caseInsensitive]
    )

    private static let leadingNumber = try! NSRegularExpression(
        pattern: #"^\s*(?:(?:ca\.?|circa|etwa|ungefähr|ungefaehr|approximately|about)\s*)?(\d+(?:[\.,]\d+)?)(?=\s|$)"#,
        options: [.caseInsensitive]
    )

    private static let leadingWordNumber = try! NSRegularExpression(
        pattern: #"^\s*(?:(?:ca\.?|circa|etwa|ungefähr|ungefaehr|approximately|about)\s*)?(ein(?:e|en|er|em|es)?|zwei|drei|vier|fünf|funf|sechs|a|an|one|two|three|four|five|six)\b"#,
        options: [.caseInsensitive]
    )

    /// A bare count can also start the next food without punctuation, e.g.
    /// `1 Kiwi 1 Nektarine`. It deliberately requires a following word so
    /// digits inside product names or barcodes are not treated as separators.
    private static let inlineBareNumber = try! NSRegularExpression(
        pattern: #"(?<![\p{L}\p{N}])(\d+(?:[\.,]\d+)?)(?=\s+[\p{L}])"#,
        options: [.caseInsensitive]
    )

    private static let inlineWordNumber = try! NSRegularExpression(
        pattern: #"(?<![\p{L}])(ein(?:e|en|er|em|es)?|zwei|drei|vier|fünf|funf|sechs|a|an|one|two|three|four|five|six)(?=\s+[\p{L}])"#,
        options: [.caseInsensitive]
    )

    static func parse(_ text: String) -> [LocalFoodTextComponent] {
        segments(in: text).compactMap(parseSegment)
    }

    private static func parseSegment(_ rawSegment: String) -> LocalFoodTextComponent? {
        let segment = rawSegment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !segment.isEmpty else { return nil }

        var parseableSegment = replacing(
            #"^(?:ich\s+(?:habe|hatte|aß|ass)|i\s+(?:had|ate))\s+"#,
            in: segment,
            with: ""
        )
        parseableSegment = normalizedEnglishFractions(in: parseableSegment)
        let quantityMatch = explicitMatch(in: parseableSegment)
            ?? leadingWordUnitMatch(in: parseableSegment)
            ?? leadingCountMatch(in: parseableSegment)
        var query = parseableSegment
        if let quantityMatch, let swiftRange = Range(quantityMatch.range, in: query) {
            query.removeSubrange(swiftRange)
        }
        query = cleanedFoodQuery(query)
        guard !query.isEmpty else { return nil }

        return LocalFoodTextComponent(
            rawText: segment,
            foodQuery: query,
            quantity: quantityMatch?.quantity,
            unit: quantityMatch?.unit
        )
    }

    private static func explicitMatch(in value: String) -> QuantityMatch? {
        let fullRange = NSRange(value.startIndex..., in: value)
        guard let match = explicitQuantity.firstMatch(in: value, range: fullRange),
              let numberRange = Range(match.range(at: 1), in: value),
              let unitRange = Range(match.range(at: 2), in: value),
              let quantity = number(String(value[numberRange])) else { return nil }
        return QuantityMatch(
            quantity: quantity,
            unit: parsedUnit(String(value[unitRange])),
            range: match.range
        )
    }

    private static func leadingCountMatch(in value: String) -> QuantityMatch? {
        let fullRange = NSRange(value.startIndex..., in: value)
        if let match = leadingNumber.firstMatch(in: value, range: fullRange),
           let numberRange = Range(match.range(at: 1), in: value),
           let quantity = number(String(value[numberRange])) {
            return QuantityMatch(quantity: quantity, unit: .count, range: match.range)
        }
        if let match = leadingWordNumber.firstMatch(in: value, range: fullRange),
           let wordRange = Range(match.range(at: 1), in: value),
           let quantity = wordNumber(String(value[wordRange])) {
            return QuantityMatch(quantity: quantity, unit: .count, range: match.range)
        }
        return nil
    }

    private static func leadingWordUnitMatch(in value: String) -> QuantityMatch? {
        let fullRange = NSRange(value.startIndex..., in: value)
        guard let match = leadingWordQuantity.firstMatch(in: value, range: fullRange),
              let numberRange = Range(match.range(at: 1), in: value),
              let unitRange = Range(match.range(at: 2), in: value),
              let quantity = wordNumber(String(value[numberRange])) else { return nil }
        return QuantityMatch(
            quantity: quantity,
            unit: parsedUnit(String(value[unitRange])),
            range: match.range
        )
    }

    private static func parsedUnit(_ rawValue: String) -> LocalFoodTextUnit {
        let value = normalized(rawValue).replacingOccurrences(of: ".", with: "")
        if value == "kg" || value.hasPrefix("kilo") { return .kilogram }
        if value == "ml" || value.hasPrefix("millil") { return .milliliter }
        if value == "l" || value.hasPrefix("liter") || value.hasPrefix("litre") { return .liter }
        if value.contains("fl oz") || value.contains("fluid") || value.contains("flussig") { return .fluidOunce }
        if value == "oz" || value.hasPrefix("ounce") || value.hasPrefix("unze") { return .ounce }
        if value.hasPrefix("portion") || value.hasPrefix("serving") { return .portion }
        if value.hasPrefix("scheib") || value.hasPrefix("slice") { return .slice }
        if value.hasPrefix("stuck") || value.hasPrefix("stueck") || value.hasPrefix("piece") { return .piece }
        if value == "teller" || value.hasPrefix("plate") { return .plate }
        if value.hasPrefix("bowl") { return .bowl }
        if value.hasPrefix("cup") { return .cup }
        if value.hasPrefix("tablespoon") || value == "tbsp" || value == "tbs" { return .tablespoon }
        if value.hasPrefix("teaspoon") || value == "tsp" { return .teaspoon }
        if value == "x" { return .piece }
        return .gram
    }

    private static func segments(in text: String) -> [String] {
        var value = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        value = replacing(#"\n+|\s*;\s*|\s+\+\s+"#, in: value, with: " ␟ ")
        value = replacing(#"\s+(?:und|mit|plus|and|with|&)\s+"#, in: value, with: " ␟ ")
        return value
            .components(separatedBy: "␟")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .flatMap(splitAtListCommas)
    }

    /// A comma can separate foods, but dictation also puts it between the
    /// amount and the *next* food ("90 g, Kiwi"). Prefer the quantity-based
    /// split only when every resulting part has both a food and an amount.
    /// Otherwise keep the comma boundary, including unquantified foods and
    /// amount-after-name lists such as "Apfel 90 g, Birne 122 g".
    private static func splitAtListCommas(_ value: String) -> [String] {
        let listComma = #",(?=\s|[^0-9]|$)"#
        let commaParts = replacing(listComma, in: value, with: " ␟ ")
            .components(separatedBy: "␟")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard commaParts.count > 1 else { return splitAtRepeatedQuantities(value) }

        let withoutListCommas = replacing(listComma, in: value, with: " ")
        let quantityParts = splitAtRepeatedQuantities(withoutListCommas)
        let namedPartCount = commaParts.compactMap(parseSegment).count
        if quantityParts.count >= namedPartCount,
           quantityParts.allSatisfy({ part in
               guard let component = parseSegment(part) else { return false }
               return component.quantity != nil && component.unit != nil
           }) {
            return quantityParts
        }
        return commaParts.flatMap(splitAtRepeatedQuantities)
    }

    /// People commonly omit separators when dictating several foods, for
    /// example "2g Ananas 1 Teller Tomatensoße". A second explicit amount can
    /// safely begin a new food only when a food name occurs between the two
    /// amounts. This keeps compound amounts such as "1 kg 500 g" together.
    private static func splitAtRepeatedQuantities(_ value: String) -> [String] {
        let fullRange = NSRange(value.startIndex..., in: value)
        let candidateMatches = explicitQuantity.matches(in: value, range: fullRange)
            + inlineBareNumber.matches(in: value, range: fullRange)
            + inlineWordNumber.matches(in: value, range: fullRange)
        // An explicit amount such as `2 oz` is also seen as a bare `2`.
        // Collapse equal start positions and retain the longest marker so the
        // text between markers contains only the actual food description.
        let matches = Dictionary(grouping: candidateMatches, by: { $0.range.location })
            .compactMap { _, values in values.max(by: { $0.range.length < $1.range.length }) }
            .sorted { $0.range.location < $1.range.location }
        guard matches.count > 1 else { return [value] }

        let source = value as NSString
        var boundaries: [Int] = []
        var previousEnd = matches[0].range.location + matches[0].range.length
        for match in matches.dropFirst() {
            let gapLength = match.range.location - previousEnd
            if gapLength > 0 {
                let gap = source.substring(with: NSRange(location: previousEnd, length: gapLength))
                if gap.rangeOfCharacter(from: .letters) != nil {
                    boundaries.append(match.range.location)
                }
            }
            previousEnd = match.range.location + match.range.length
        }
        guard !boundaries.isEmpty else { return [value] }

        var result: [String] = []
        var start = 0
        for boundary in boundaries + [source.length] {
            let part = source.substring(with: NSRange(location: start, length: boundary - start))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !part.isEmpty { result.append(part) }
            start = boundary
        }
        return result
    }

    private static func cleanedFoodQuery(_ rawValue: String) -> String {
        var value = rawValue
        value = replacing(#"\b(?:ca\.?|circa|etwa|ungefähr|ungefaehr|approximately|about)\b"#, in: value, with: " ")
        value = replacing(#"^(?:ich\s+(?:habe|hatte|aß|ass)|i\s+(?:had|ate))\s+"#, in: value, with: " ")
        value = replacing(#"\b(?:gegessen|getrunken|verzehrt|eaten|drunk)\b"#, in: value, with: " ")
        value = replacing(#"\bof\b"#, in: value, with: " ")
        value = replacing(#"[\[\]\(\){}:,]"#, in: value, with: " ")
        value = replacing(#"\s+"#, in: value, with: " ")
        return value.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }

    private static func number(_ value: String) -> Double? {
        Double(value.replacingOccurrences(of: ",", with: "."))
    }

    private static func wordNumber(_ rawValue: String) -> Double? {
        switch normalized(rawValue) {
        case "ein", "eine", "einen", "einer", "einem", "eines", "a", "an", "one": 1
        case "zwei", "two": 2
        case "drei", "three": 3
        case "vier", "four": 4
        case "funf", "five": 5
        case "sechs", "six": 6
        default: nil
        }
    }

    private static func normalized(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "de_DE"))
            .lowercased()
            .replacingOccurrences(of: "ß", with: "ss")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedEnglishFractions(in value: String) -> String {
        var result = value
            .replacingOccurrences(of: "½", with: "0.5")
            .replacingOccurrences(of: "¼", with: "0.25")
            .replacingOccurrences(of: "¾", with: "0.75")
        result = replacing(#"(?<!\d)1\s*/\s*2(?!\d)"#, in: result, with: "0.5")
        result = replacing(#"(?<!\d)1\s*/\s*4(?!\d)"#, in: result, with: "0.25")
        result = replacing(#"(?<!\d)3\s*/\s*4(?!\d)"#, in: result, with: "0.75")
        result = replacing(#"^\s*half(?:\s+of)?(?:\s+(?:a|an))?\s+"#, in: result, with: "0.5 ")
        result = replacing(#"^\s*(?:a\s+)?quarter(?:\s+of)?(?:\s+(?:a|an))?\s+"#, in: result, with: "0.25 ")
        return result
    }

    private static func replacing(_ pattern: String, in value: String, with replacement: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return value }
        let range = NSRange(value.startIndex..., in: value)
        return expression.stringByReplacingMatches(in: value, range: range, withTemplate: replacement)
    }
}
