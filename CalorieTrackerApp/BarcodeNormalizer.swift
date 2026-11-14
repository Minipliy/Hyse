import Foundation

nonisolated enum BarcodeValidationError: LocalizedError, Equatable {
    case empty, unsupportedLength, invalidCharacters, invalidCheckDigit

    var errorDescription: String? {
        switch self {
        case .empty: return LanguageStore.localizedString("barcode.invalid_empty")
        case .unsupportedLength: return LanguageStore.localizedString("barcode.invalid_length")
        case .invalidCharacters: return LanguageStore.localizedString("barcode.invalid_characters")
        case .invalidCheckDigit: return LanguageStore.localizedString("barcode.invalid_check_digit")
        }
    }
}

nonisolated enum BarcodeNormalizer {
    /// Canonical GTIN representation. Leading zeroes are deliberately retained.
    static func normalize(_ raw: String) throws -> String {
        let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "-–—."))
        let cleaned = raw.unicodeScalars.filter { !separators.contains($0) }.map(String.init).joined()
        guard !cleaned.isEmpty else { throw BarcodeValidationError.empty }
        guard cleaned.allSatisfy(\.isNumber) else { throw BarcodeValidationError.invalidCharacters }
        guard [8, 12, 13, 14].contains(cleaned.count) else { throw BarcodeValidationError.unsupportedLength }
        guard hasValidGTINCheckDigit(cleaned) else { throw BarcodeValidationError.invalidCheckDigit }
        return cleaned
    }

    static func normalizedIfValid(_ raw: String?) -> String? {
        guard let raw else { return nil }
        return try? normalize(raw)
    }

    private static func hasValidGTINCheckDigit(_ value: String) -> Bool {
        let digits = value.compactMap(\.wholeNumberValue)
        guard digits.count == value.count, let expected = digits.last else { return false }
        var sum = 0
        for (offset, digit) in digits.dropLast().reversed().enumerated() {
            sum += digit * (offset.isMultiple(of: 2) ? 3 : 1)
        }
        return (10 - (sum % 10)) % 10 == expected
    }
}
