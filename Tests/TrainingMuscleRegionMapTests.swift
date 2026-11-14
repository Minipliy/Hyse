import SwiftUI

// Minimal visual-style fixtures allow the production body and mapping file to
// compile as a standalone executable test.
enum HyseColor {
    static let accent = Color.blue
}

enum HyseRadius {
    static let card: CGFloat = 18
}

@main
struct TrainingMuscleRegionMapTests {
    static func main() {
        let bicepsCurl = TrainingMuscleRegionMap.weightedRegions(
            primary: ["biceps"],
            secondary: ["forearms"]
        )
        expect(bicepsCurl == ["biceps": 1], "a biceps curl must only colour biceps")

        let requestedCombination = [
            TrainingMuscleRegionMap.weightedRegions(primary: ["quadriceps"], secondary: []),
            TrainingMuscleRegionMap.weightedRegions(primary: ["upper_back", "lats"], secondary: ["biceps", "forearms", "rear_shoulders"]),
            TrainingMuscleRegionMap.weightedRegions(primary: ["calves"], secondary: [])
        ]
        .reduce(into: Set<String>()) { result, regions in
            result.formUnion(regions.keys)
        }
        expect(
            requestedCombination == Set(["quadriceps", "upper_back", "lats", "calves"]),
            "leg extension, row and calf raise must colour exactly their target muscles"
        )

        expect(TrainingMuscleRegionMap.regions(for: "arms").isEmpty, "ambiguous arm tags must not fan out")
        expect(TrainingMuscleRegionMap.regions(for: "legs").isEmpty, "ambiguous leg tags must not fan out")
        expect(TrainingMuscleRegionMap.regions(for: "tibialis") == ["tibialis"], "tibialis must be separate from calves")

        let maskKeys = Set(TrainingAnatomicalMuscle.allCases.map(\.rawValue))
        expect(requestedCombination.isSubset(of: maskKeys), "every requested target needs an independent mask")
        expect(maskKeys.contains("tibialis"), "the anterior shin needs an independent mask")

        print("TrainingMuscleRegionMapTests: all checks passed")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fatalError("FAILED: \(message)") }
    }
}
