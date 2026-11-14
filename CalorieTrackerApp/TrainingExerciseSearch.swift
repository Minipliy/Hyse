import Foundation

/// Shared search for the exercise picker and the routine editor.
nonisolated enum TrainingExerciseSearch {
    static func score(
        _ exercise: TrainingExercise,
        query: String,
        isGerman: Bool,
        muscleName: (String) -> String
    ) -> Int? {
        let terms = words(in: query)
        guard !terms.isEmpty else { return 0 }

        let names = [
            exercise.displayName(isGerman: isGerman),
            exercise.germanName,
            exercise.englishName
        ]
        let nameWords: [(word: String, penalty: Int)] = names.flatMap(words(in:)).flatMap { word in
            [(word, 0)] + compoundParts
                .filter { word != $0 && word.contains($0) }
                .map { ($0, 3) }
        }
        func muscleWords(_ identifier: String) -> [String] {
            words(in: muscleName(identifier))
                + words(in: identifier.replacingOccurrences(of: "_", with: " "))
                + words(in: muscleAliases[identifier, default: ""])
        }
        let primaryWords = exercise.primaryMuscles.map(muscleWords)
        let secondaryWords = exercise.secondaryMuscles.map(muscleWords)
        let equipmentWords = words(in: equipmentAliases[exercise.equipment, default: ""])

        var score = 0
        for term in terms {
            let nameMatch = term == "po"
                ? nameWords.contains(where: { $0.word == "po" }) ? 0 : nil
                : nameWords.compactMap { entry in
                    wordScore(term, against: entry.word).map { $0 + entry.penalty }
                }.min()
            let primaryMatch = primaryWords.enumerated().compactMap { index, words -> Int? in
                guard let match = words.compactMap({ wordScore(term, against: $0) }).min() else { return nil }
                return (match == 0 ? 1 : match >= 7 ? match + 5 : max(3, match - 3))
                    + index * 3
                    + (exercise.equipment == .cardio ? 12 : 0)
            }.min()
            let secondaryMatch = secondaryWords.compactMap { words in
                words.compactMap { wordScore(term, against: $0) }.min().map { $0 + 15 }
            }.min()
            let equipmentMatch = equipmentWords.compactMap { wordScore(term, against: $0) }
                .min().map { $0 + 9 }
            guard let best = [nameMatch, primaryMatch, secondaryMatch, equipmentMatch].compactMap({ $0 }).min() else { return nil }
            score += best
        }
        return score
    }

    private static let muscleAliases: [String: String] = [
        "chest": "brust pectorals pecs",
        "back": "rücken ruecken back",
        "upper_back": "oberer rücken ruecken traps",
        "lower_back": "unterer rücken ruecken",
        "lats": "lat latissimus rücken ruecken",
        "shoulders": "schulter delts",
        "front_shoulders": "vordere schulter delts",
        "rear_shoulders": "hintere schulter delts",
        "biceps": "bizeps oberarm arme",
        "triceps": "trizeps oberarm arme",
        "forearms": "unterarm griffkraft grip",
        "core": "bauch bauchmuskeln abs rumpf",
        "obliques": "seitlicher bauch seitliche bauchmuskeln",
        "quadriceps": "beine oberschenkel quads",
        "hamstrings": "beine hinterer oberschenkel",
        "glutes": "po gesäß gessaess gluteus",
        "calves": "waden unterschenkel",
        "adductors": "adduktoren innenschenkel",
        "abductors": "abduktoren außenschenkel aussenschenkel",
        "hip_flexors": "hüftbeuger hueftbeuger",
        "tibialis": "schienbein schienbeinmuskel"
    ]

    private static let equipmentAliases: [TrainingEquipment: String] = [
        .barbell: "langhantel barbell hantel",
        .dumbbell: "kurzhantel kurzhanteln dumbbell hantel",
        .kettlebell: "kettlebell kugelhantel",
        .machine: "maschine gerät geraet machine",
        .cable: "kabel kabelzug cable",
        .bodyweight: "körpergewicht koerpergewicht bodyweight",
        .bands: "band widerstandsband resistance band",
        .cardio: "cardio ausdauer",
        .other: ""
    ]

    private static let compoundParts = [
        "bankdrucken", "drucken", "rudern", "kabel", "brust", "schulter",
        "bizeps", "trizeps", "kniebeuge", "kreuzheben", "wadenheben",
        "beinheben", "beinbeuger", "kurzhantel", "langhantel", "latzug"
    ]

    private static func words(in value: String) -> [String] {
        let normalized = value
            .lowercased()
            .replacingOccurrences(of: "ß", with: "ss")
            .folding(options: [.diacriticInsensitive], locale: Locale(identifier: "de_DE"))
        return normalized
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    private static func wordScore(_ term: String, against word: String) -> Int? {
        if term == word { return 0 }
        if word.hasPrefix(term) { return 2 }
        if term.count >= 3 && word.contains(term) { return 4 }
        guard term.count >= 4 else { return nil }
        let allowedErrors = term.count >= 8 ? 2 : 1
        if abs(term.count - word.count) <= allowedErrors,
           let errors = editDistance(term, word, limit: allowedErrors) {
            return 7 + errors
        }

        // A query is often only the beginning of a longer exercise name.
        // Compare nearby prefix lengths so a typo in "beim" can still find
        // "Beinstrecker" without requiring the whole word to be entered.
        let letters = Array(word)
        let shortestPrefix = max(1, term.count - allowedErrors)
        let longestPrefix = min(letters.count, term.count + allowedErrors)
        guard shortestPrefix <= longestPrefix else { return nil }
        let errors = (shortestPrefix...longestPrefix)
            .compactMap { length in
                editDistance(term, String(letters.prefix(length)), limit: allowedErrors)
            }
            .min()
        return errors.map { 7 + $0 }
    }

    /// Damerau-Levenshtein distance for a single swapped pair as well as
    /// missing, extra, or mistyped letters.
    private static func editDistance(_ lhs: String, _ rhs: String, limit: Int) -> Int? {
        let a = Array(lhs)
        let b = Array(rhs)
        var matrix = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in 0...a.count { matrix[i][0] = i }
        for j in 0...b.count { matrix[0][j] = j }
        for i in 1...a.count {
            var rowMinimum = Int.max
            for j in 1...b.count {
                let substitution = a[i - 1] == b[j - 1] ? 0 : 1
                var cost = min(
                    matrix[i - 1][j] + 1,
                    matrix[i][j - 1] + 1,
                    matrix[i - 1][j - 1] + substitution
                )
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                    cost = min(cost, matrix[i - 2][j - 2] + 1)
                }
                matrix[i][j] = cost
                rowMinimum = min(rowMinimum, cost)
            }
            if rowMinimum > limit { return nil }
        }
        return matrix[a.count][b.count] <= limit ? matrix[a.count][b.count] : nil
    }
}
