import Foundation

@main
struct LocalFoodTextParserTests {
    static func main() {
        expect("45g Proteinpulver", query: "Proteinpulver", amount: 45, unit: .gram)
        expect("45 g Proteinpulver", query: "Proteinpulver", amount: 45, unit: .gram)
        expect("Proteinpulver 45g", query: "Proteinpulver", amount: 45, unit: .gram)
        expect("Proteinpulver 45 Gramm", query: "Proteinpulver", amount: 45, unit: .gram)
        expect("10g Ananas", query: "Ananas", amount: 10, unit: .gram)
        expect("1 Scheibe Apfel", query: "Apfel", amount: 1, unit: .slice)
        expect("1,5 Portionen Haferflocken", query: "Haferflocken", amount: 1.5, unit: .portion)
        expect("1.5 portions oats", query: "oats", amount: 1.5, unit: .portion)
        expect("2x Ei", query: "Ei", amount: 2, unit: .piece)
        expect("2 Eier", query: "Eier", amount: 2, unit: .count)
        expect("ein Apfel", query: "Apfel", amount: 1, unit: .count)
        expect("250ml Milch", query: "Milch", amount: 250, unit: .milliliter)
        expect("Milch 0,5 l", query: "Milch", amount: 0.5, unit: .liter)
        expect("0.5kg Reis", query: "Reis", amount: 0.5, unit: .kilogram)
        expect("2 fl. oz. Milch", query: "Milch", amount: 2, unit: .fluidOunce)
        expect("ca. 150 g Hähnchen", query: "Hähnchen", amount: 150, unit: .gram)
        expect("Ich hatte 2 Eier", query: "Eier", amount: 2, unit: .count)
        expect("1 Teller Tomatensoße", query: "Tomatensoße", amount: 1, unit: .plate)
        expect("one slice of toast", query: "toast", amount: 1, unit: .slice)
        expect("a bowl of tomato soup", query: "tomato soup", amount: 1, unit: .bowl)
        expect("half a cup of milk", query: "milk", amount: 0.5, unit: .cup)
        expect("1/2 cup oats", query: "oats", amount: 0.5, unit: .cup)
        expect("2 tbsp peanut butter", query: "peanut butter", amount: 2, unit: .tablespoon)
        expect("1 tsp olive oil", query: "olive oil", amount: 1, unit: .teaspoon)

        expectList(
            "45g Proteinpulver, 250ml Milch und 1 Banane",
            expected: [("Proteinpulver", 45, .gram), ("Milch", 250, .milliliter), ("Banane", 1, .count)]
        )
        expectList(
            "150 g Hähnchen mit 200g Reis; 10g Butter",
            expected: [("Hähnchen", 150, .gram), ("Reis", 200, .gram), ("Butter", 10, .gram)]
        )
        expectList(
            "Whey\nBanane\nMilch",
            expected: [("Whey", nil, nil), ("Banane", nil, nil), ("Milch", nil, nil)]
        )
        expectList(
            "2g Ananas 1 Teller Tomatensoße",
            expected: [("Ananas", 2, .gram), ("Tomatensoße", 1, .plate)]
        )
        expectList(
            "1 Kiwi 1 Nektarine",
            expected: [("Kiwi", 1, .count), ("Nektarine", 1, .count)]
        )
        expectList(
            "one kiwi one nectarine",
            expected: [("kiwi", 1, .count), ("nectarine", 1, .count)]
        )
        expectList(
            "45g Proteinpulver 1 Banane",
            expected: [("Proteinpulver", 45, .gram), ("Banane", 1, .count)]
        )
        expectList(
            "45g Proteinpulver 250ml Milch",
            expected: [("Proteinpulver", 45, .gram), ("Milch", 250, .milliliter)]
        )
        expectList(
            "2 oz chicken breast 1 cup cooked rice",
            expected: [("chicken breast", 2, .ounce), ("cooked rice", 1, .cup)]
        )
        let mixedPunctuation = "92 g Apfel, 122 g Birne, 101 g Banane 90 g, Kiwi 186 g, Gurke 117 g Paprika, 74 g Karotte"
        let sevenFoods: [(String, Double?, LocalFoodTextUnit?)] = [
            ("Apfel", 92, .gram), ("Birne", 122, .gram), ("Banane", 101, .gram),
            ("Kiwi", 90, .gram), ("Gurke", 186, .gram), ("Paprika", 117, .gram),
            ("Karotte", 74, .gram)
        ]
        expectList(mixedPunctuation, expected: sevenFoods)
        expectList(mixedPunctuation.replacingOccurrences(of: ", ", with: " "), expected: sevenFoods)
        expectList("Apfel 90 g, Birne 122 g", expected: [("Apfel", 90, .gram), ("Birne", 122, .gram)])
        expectList("90 g, Kiwi", expected: [("Kiwi", 90, .gram)])
        expectList("Apfel, Birne, Banane", expected: [("Apfel", nil, nil), ("Birne", nil, nil), ("Banane", nil, nil)])
        expectList("100 g Reis, Apfel", expected: [("Reis", 100, .gram), ("Apfel", nil, nil)])
        expectList("1,5 Portionen Haferflocken, 2 Eier", expected: [("Haferflocken", 1.5, .portion), ("Eier", 2, .count)])

        print("LocalFoodTextParserTests: all formats passed")
    }

    private static func expect(_ input: String, query: String, amount: Double?, unit: LocalFoodTextUnit?) {
        let values = LocalFoodTextParser.parse(input)
        check(values.count == 1, "\(input): expected one food, got \(values)")
        guard let value = values.first else { return }
        check(value.foodQuery == query, "\(input): expected query \(query), got \(value.foodQuery)")
        check(equal(value.quantity, amount), "\(input): expected amount \(String(describing: amount)), got \(String(describing: value.quantity))")
        check(value.unit == unit, "\(input): expected unit \(String(describing: unit)), got \(String(describing: value.unit))")
    }

    private static func expectList(
        _ input: String,
        expected: [(String, Double?, LocalFoodTextUnit?)]
    ) {
        let values = LocalFoodTextParser.parse(input)
        check(values.count == expected.count, "\(input): expected \(expected.count) foods, got \(values.count)")
        for (value, expectedValue) in zip(values, expected) {
            check(value.foodQuery == expectedValue.0, "\(input): expected \(expectedValue.0), got \(value.foodQuery)")
            check(equal(value.quantity, expectedValue.1), "\(input): wrong amount for \(expectedValue.0)")
            check(value.unit == expectedValue.2, "\(input): wrong unit for \(expectedValue.0)")
        }
    }

    private static func equal(_ lhs: Double?, _ rhs: Double?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): true
        case let (left?, right?): abs(left - right) < 0.000_001
        default: false
        }
    }

    private static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fatalError("FAILED: \(message)") }
    }
}
