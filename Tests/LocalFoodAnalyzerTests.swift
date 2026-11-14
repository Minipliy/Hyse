import Foundation

#if canImport(FoundationModels)
@available(iOS 26.0, *)
nonisolated enum AppleFoodLanguageParser {
    static func parse(_ input: String) async -> [LocalFoodTextComponent]? { nil }
}
#endif

@MainActor
final class LanguageStore {
    var isGerman = true
    func text(_ key: String) -> String { key }
}

@main
struct LocalFoodAnalyzerTests {
    static func main() async {
        let powder = food("Proteinpulver", portion: 60)
        let oats = food("Haferflocken", portion: 60)
        let pineapple = food("Ananas")
        let apple = food("Apfel")
        let egg = food("Ei")
        let milk = food("Milch", unit: .milliliter)
        let tomatoSauce = food("Tomatensoße", portion: 250)
        let chickenBreast = food("Hähnchenbrust", portion: 150)
        let rice = food("Reis", portion: 180)
        let toast = food("Toastbrot")
        let peanutButter = food("Erdnussbutter")
        let banana = food("Banane")
        let pear = food("Birne")
        let kiwi = food("Kiwi", portion: 75)
        let cucumber = food("Gurke")
        let pepper = food("Paprika")
        let carrot = food("Karotte")
        let nectarine = food("Nektarine", portion: 140)
        let foods = [oats, powder, pineapple, apple, egg, milk, tomatoSauce, chickenBreast, rice, toast, peanutButter, banana, pear, kiwi, cucumber, pepper, carrot, nectarine]

        await expect("45g Proteinpulver", foods: foods, food: powder, amount: 45)
        await expect("Proteinpulver 45 g", foods: foods, food: powder, amount: 45)
        await expect("1,5 Portionen Haferflocken", foods: foods, food: oats, amount: 90)
        await expect("10g Anananas", foods: foods, food: pineapple, amount: 10)
        await expect("1 Scheibe Apfel", foods: foods, food: apple, amount: 25)
        await expect("2 Eier", foods: foods, food: egg, amount: 120)
        await expect("250ml Milch", foods: foods, food: milk, amount: 250)

        let tomato = food("Tomatoes, red, ripe, raw", portion: 123)
        let germanTomato = FoodItem(name: tomato.name, nameDE: "Tomate, rot, roh", kcalPer100g: 18)
        let spread = food("Tomaten-Basilikum-Aufstrich")
        let sauce = food("Tomato sauce")
        await expect("53g tomate", foods: [spread, sauce, germanTomato], food: germanTomato, amount: 53)
        await expect("53g Tomaten-Basilikum-Aufstrich", foods: [germanTomato, spread], food: spread, amount: 53)
        await expect("53g tomato", foods: [sauce, tomato], food: tomato, amount: 53)
        await expectNoMatch("53g tomate", foods: [spread, sauce])
        await expectNoMatch("53g tomato sauce", foods: [tomato])

        let appleSpread = food("Apfel-Zimt-Aufstrich")
        await expect("80g Apfel", foods: [appleSpread, apple], food: apple, amount: 80)
        await expectNoMatch("80g Apfel", foods: [appleSpread])

        let multiple = await LocalFoodAnalyzer.shared.analyzeText(
            "45g Proteinpulver, 250ml Milch und 1 Banane",
            foods: foods + [food("Banane")]
        )
        check(multiple.count == 3, "expected three separate foods, got \(multiple.count)")
        check(multiple.first(where: { $0.food.id == powder.id })?.baseAmount == 45, "powder amount changed in a meal")
        check(multiple.first(where: { $0.food.id == milk.id })?.baseAmount == 250, "milk amount changed in a meal")

        let mixedPunctuationMeal = await LocalFoodAnalyzer.shared.analyzeText(
            "92 g Apfel, 122 g Birne, 101 g Banane 90 g, Kiwi 186 g, Gurke 117 g Paprika, 74 g Karotte",
            foods: foods
        )
        let expectedMixed: [(FoodItem, Double)] = [
            (apple, 92), (pear, 122), (banana, 101), (kiwi, 90),
            (cucumber, 186), (pepper, 117), (carrot, 74)
        ]
        check(mixedPunctuationMeal.count == expectedMixed.count, "mixed commas must retain all seven foods")
        for (match, expected) in zip(mixedPunctuationMeal, expectedMixed) {
            check(match.food.id == expected.0.id, "mixed commas changed food order or identity")
            check(abs(match.baseAmount - expected.1) < 0.000_001, "mixed commas changed a food quantity")
        }

        let unseparatedMeal = await LocalFoodAnalyzer.shared.analyzeText(
            "2g Ananas 1 Teller Tomatensoße",
            foods: foods
        )
        check(unseparatedMeal.count == 2, "unseparated meal must retain both foods")
        check(unseparatedMeal.first(where: { $0.food.id == pineapple.id })?.baseAmount == 2, "2 g must stay attached to pineapple")
        check(unseparatedMeal.first(where: { $0.food.id == tomatoSauce.id })?.baseAmount == 250, "one plate must use the tomato-sauce portion")

        let bareCountMeal = await LocalFoodAnalyzer.shared.analyzeText(
            "1 Kiwi 1 Nektarine",
            foods: foods
        )
        check(bareCountMeal.count == 2, "bare counts without punctuation must retain both foods")
        check(bareCountMeal.first(where: { $0.food.id == kiwi.id })?.baseAmount == 75, "one kiwi must use its saved portion")
        check(bareCountMeal.first(where: { $0.food.id == nectarine.id })?.baseAmount == 140, "one nectarine must use its saved portion")

        let englishMeal = await LocalFoodAnalyzer.shared.analyzeText(
            "2 oz chicken breast 1 cup cooked rice",
            foods: foods
        )
        check(englishMeal.count == 2, "English meal without punctuation must retain both foods")
        check(abs((englishMeal.first(where: { $0.food.id == chickenBreast.id })?.baseAmount ?? 0) - 56.699_046_25) < 0.000_001, "English ounces must convert to grams")
        check(englishMeal.first(where: { $0.food.id == rice.id })?.baseAmount == 180, "English cup must use the saved rice portion")

        await expect("one slice of toast", foods: foods, food: toast, amount: 45)
        await expect("half a cup of milk", foods: foods, food: milk, amount: 118.294)
        await expect("I ate three scrambled eggs", foods: foods, food: egg, amount: 180)

        let englishEverydayMeal = await LocalFoodAnalyzer.shared.analyzeText(
            "1 tbsp peanut butter and a medium banana",
            foods: foods
        )
        check(englishEverydayMeal.count == 2, "English article and household unit must retain both foods")
        check(englishEverydayMeal.first(where: { $0.food.id == peanutButter.id })?.baseAmount == 15, "tablespoon fallback must be stable")
        check(englishEverydayMeal.first(where: { $0.food.id == banana.id })?.baseAmount == 120, "English article must represent one banana")

        print("LocalFoodAnalyzerTests: all catalogue and amount checks passed")
    }

    private static func food(_ name: String, unit: FoodUnit = .gram, portion: Double? = nil) -> FoodItem {
        FoodItem(name: name, kcalPer100g: 100, unit: unit, servingSizeAmount: portion)
    }

    private static func expect(
        _ input: String,
        foods: [FoodItem],
        food: FoodItem,
        amount: Double
    ) async {
        let values = await LocalFoodAnalyzer.shared.analyzeText(input, foods: foods)
        check(values.count == 1, "\(input): expected one result, got \(values.count)")
        guard let value = values.first else { return }
        check(value.food.id == food.id, "\(input): expected \(food.name), got \(value.food.name)")
        check(abs(value.baseAmount - amount) < 0.000_001, "\(input): expected \(amount), got \(value.baseAmount)")
    }

    private static func expectNoMatch(_ input: String, foods: [FoodItem]) async {
        let values = await LocalFoodAnalyzer.shared.analyzeText(input, foods: foods)
        check(values.isEmpty, "\(input): unrelated product was selected: \(values.map(\.food.name))")
    }

    private static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fatalError("FAILED: \(message)") }
    }
}
