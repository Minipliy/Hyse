import Foundation

nonisolated enum TrainingExerciseType: String, Codable, CaseIterable, Identifiable, Sendable {
    case weightReps = "weight_reps"
    case bodyweight
    case duration
    case distanceDuration = "distance_duration"
    case repsOnly = "reps_only"
    var id: String { rawValue }
    var localizationKey: String { "training.exercise_type.\(rawValue)" }
}

nonisolated enum TrainingEquipment: String, Codable, CaseIterable, Identifiable, Sendable {
    case barbell, dumbbell, kettlebell, machine, cable, bodyweight, bands, cardio, other
    var id: String { rawValue }
    var localizationKey: String { "training.equipment.\(rawValue)" }
}

nonisolated enum ExerciseVisualKind: String, Sendable {
    case press, row, squat, hinge, pull, raise, curl, core, lunge
    case run, cycle, rowing, jump, kettlebell, generic

    var instructionKey: String { "training.exercise.motion.\(rawValue).instruction" }
    var techniqueKey: String { "training.exercise.motion.\(rawValue).technique" }
}

nonisolated enum TrainingSetType: String, Codable, CaseIterable, Identifiable, Sendable {
    case normal, warmup, dropSet = "drop_set", failure, superset
    var id: String { rawValue }
    var localizationKey: String { "training.set_type.\(rawValue)" }
}

nonisolated enum TrainingWeightUnit: String, Codable, CaseIterable, Identifiable, Sendable {
    case kilograms = "kg"
    case pounds = "lb"
    var id: String { rawValue }
    var localizationKey: String { "training.unit.\(rawValue)" }
    func display(_ kilograms: Double) -> Double { self == .kilograms ? kilograms : kilograms * 2.204_622_621_8 }
    func kilograms(_ displayed: Double) -> Double { self == .kilograms ? displayed : displayed / 2.204_622_621_8 }
}

nonisolated enum TrainingDistanceUnit: String, Codable, CaseIterable, Identifiable, Sendable {
    case kilometers = "km"
    case miles = "mi"
    var id: String { rawValue }
    var localizationKey: String { "training.unit.\(rawValue)" }
    var metersPerUnit: Double { self == .kilometers ? 1_000 : 1_609.344 }
    func display(_ meters: Double) -> Double { meters / metersPerUnit }
    func meters(_ displayed: Double) -> Double { displayed * metersPerUnit }
    func paceSeconds(durationSeconds: Double, distanceMeters: Double) -> Double? {
        guard durationSeconds > 0, distanceMeters > 0 else { return nil }
        return durationSeconds / display(distanceMeters)
    }
}

nonisolated struct TrainingExercise: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var remoteID: String?
    var nameKey: String
    var englishName: String
    var germanName: String
    var descriptionKey: String
    var techniqueKey: String
    var type: TrainingExerciseType
    var equipment: TrainingEquipment
    var primaryMuscles: [String]
    var secondaryMuscles: [String]
    var isCustom: Bool
    var isFavorite: Bool
    var updatedAt: Date
    /// A compact, user-selected image for private custom exercises.
    /// Keeping it in the exercise snapshot makes it available offline and on
    /// the user's other devices without adding a separate public media record.
    var customImageData: Data? = nil
    /// Explicit choice for custom exercises; nil keeps legacy catalog/name inference.
    var isUnilateral: Bool? = nil

    func displayName(isGerman: Bool) -> String {
        // Saved routines and workout snapshots keep their embedded exercise
        // metadata. Resolve this curated rename by key so it also appears in
        // existing history without rewriting user data.
        if isGerman && nameKey == "cable_biceps_curl" {
            return "Bizepscurl am Kabelturm"
        }
        return isGerman && !germanName.isEmpty ? germanName : englishName
    }

    func initials(isGerman: Bool) -> String {
        // German exercise names are often compound words. Taking their first
        // letters literally produces codes such as "Sc" for
        // "Schulterdrücken", which are not useful in a small exercise tile.
        // Keep the compact labels curated for the built-in catalog and use the
        // name-based fallback for custom/imported exercises.
        if isGerman, let germanInitials = Self.germanInitials[nameKey] {
            return germanInitials
        }

        let localizedName = displayName(isGerman: isGerman).trimmingCharacters(in: .whitespacesAndNewlines)
        let name = (localizedName.isEmpty ? englishName : localizedName).trimmingCharacters(in: .whitespacesAndNewlines)
        let words = name
            .replacingOccurrences(of: "&", with: " and ")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map { $0.lowercased() }
            .filter { !$0.isEmpty && !Self.initialStopWords.contains($0) }

        guard !words.isEmpty else {
            return String(name.prefix(2)).uppercased()
        }

        // Keep the exercise movement at the end of the abbreviation and use
        // the first/last useful modifier to distinguish variants:
        // "Incline Dumbbell Press" -> IDP, "Cable Glute Kickback" -> CGK.
        var selected = Array(words.prefix(3))
        if let movementIndex = words.lastIndex(where: { Self.initialMovementWords.contains($0) }) {
            let descriptors = Array(words[..<movementIndex])
            if descriptors.isEmpty {
                selected = Array(words[max(0, movementIndex - 1)...movementIndex])
            } else {
                let first = descriptors[0]
                let lastSemantic = descriptors.last(where: { !Self.initialEquipmentWords.contains($0) })
                let second = lastSemantic.flatMap { $0 == first ? nil : $0 }
                    ?? (descriptors.count > 1 ? descriptors.last : nil)
                selected = [first]
                if let second {
                    selected.append(second)
                }
                selected.append(words[movementIndex])
            }
        }

        if selected.count == 1, let word = selected.first {
            if let compactWord = Self.compactWordInitials[word] {
                return compactWord
            }
            return String(word.prefix(2)).uppercased()
        }
        return selected
            .prefix(3)
            .compactMap { $0.first.map(String.init) }
            .joined()
        .uppercased()
    }

    private static let compactWordInitials: [String: String] = [
        "schulterdrücken": "SD",
        "bankdrücken": "BD",
        "kniebeuge": "KB",
        "kreuzheben": "KH",
        "klimmzug": "KZ",
        "liegestütz": "LS",
        "unterarmstütz": "US",
        "seitheben": "SH",
        "wadenheben": "WH",
        "beinpresse": "BP",
        "beinstrecker": "BS",
        "latzug": "LZ",
        "rudern": "RU",
        "bizepscurls": "BC",
        "hammercurls": "HC",
        "seilspringen": "SS",
        "laufband": "LB",
        "ergometer": "ER",
        "ruderergometer": "RE",
        "crosstrainer": "CT",
        "treppensteiger": "TS"
    ]

    /// Short labels for the German catalog. These are intentionally based on
    /// the movement name first and the equipment/variation second, so the
    /// letters remain recognizable even when the full name is hidden.
    private static let germanInitials: [String: String] = [
        "barbell_bench_press": "LBD",
        "barbell_back_squat": "LHK",
        "conventional_deadlift": "KH",
        "overhead_press": "SD",
        "pull_up": "KZ",
        "dumbbell_row": "KHR",
        "lat_pulldown": "LZ",
        "leg_press": "BP",
        "push_up": "LS",
        "plank": "US",
        "treadmill_run": "LB",
        "band_face_pull": "BFP",
        "incline_dumbbell_press": "SKD",
        "lateral_raise": "SH",
        "biceps_curl": "BC",
        "triceps_pushdown": "TK",
        "standing_calf_raise": "WS",
        "barbell_row": "LHR",
        "romanian_deadlift": "RKH",
        "hip_thrust": "HT",
        "cable_glute_kickback": "GKC",
        "leg_extension": "BS",
        "chest_fly_machine": "BM",
        "seated_cable_row": "SKR",
        "dumbbell_shoulder_press": "KSD",
        "dumbbell_rdl": "RKH",
        "goblet_squat": "GS",
        "hammer_curl": "HC",
        "bodyweight_squat": "KB",
        "reverse_lunge": "AR",
        "glute_bridge": "GB",
        "pike_push_up": "PP",
        "mountain_climber": "MC",
        "band_squat": "KMB",
        "band_row": "BR",
        "band_chest_press": "BB",
        "band_rdl": "RKB",
        "band_lateral_raise": "SHB",
        "kettlebell_swing": "KS",
        "kettlebell_goblet": "KGS",
        "kettlebell_press": "KCP",
        "kettlebell_row": "KR",
        "outdoor_run": "LD",
        "stationary_bike": "ER",
        "rowing_ergometer": "RE",
        "jump_rope": "SS",
        "incline_barbell_press": "SLD",
        "decline_barbell_press": "NLD",
        "closegrip_bench_press": "EB",
        "dumbbell_chest_fly": "FK",
        "dumbbell_pullover": "KP",
        "arnold_shoulder_press": "AP",
        "upright_barbell_row": "ALR",
        "tbar_supported_row": "TBR",
        "barbell_shrug": "SL",
        "ezbar_biceps_curl": "SZC",
        "preacher_biceps_curl": "PC",
        "concentration_curl": "KC",
        "reverse_barbell_curl": "RLC",
        "zottman_curl": "ZC",
        "wrist_roller": "UR",
        "skullcrusher_ezbar": "FS",
        "goodmorning_barbell": "GM",
        "donkey_calf_raise": "DW",
        "machine_chest_press": "BPM",
        "machine_shoulder_press": "SP",
        "smith_incline_press": "MSD",
        "cable_fly_low_high": "KFU",
        "cable_lateral_raise": "SK",
        "reverse_pecdeck_fly": "RB",
        "supported_chest_row": "BRR",
        "onearm_cable_row": "EKR",
        "straightarm_pulldown": "KP",
        "onearm_lat_pulldown": "EL",
        "assisted_pullup_machine": "UK",
        "incline_db_biceps_curl": "SKS",
        "bayesian_cable_curl": "BK",
        "overhead_cable_triceps": "ÜTS",
        "cable_triceps_kickback": "TK",
        "hack_squat_machine": "HK",
        "pendulum_squat_machine": "PK",
        "smith_squat_machine": "MK",
        "bulgarian_split_squat": "BKS",
        "walking_dumbbell_lunge": "GKA",
        "seated_hamstring_curl": "BS",
        "lying_hamstring_curl": "BL",
        "hip_abduction_machine": "AMA",
        "hip_adduction_machine": "AMD",
        "nordic_hamstring_curl": "NHC",
        "back_extension_45deg": "45H",
        "seated_calf_machine": "WS",
        "bodyweight_dip": "DIP",
        "weighted_dip": "DZ",
        "chinup_supinated": "KUG",
        "cable_ab_crunch": "KK",
        "hanging_leg_raise": "BH",
        "abwheel_rollout": "AR",
        "elliptical_trainer": "CT",
        "stairclimber_cardio": "TS",
        "airbike_cardio": "AB"
    ]

    private static let initialStopWords: Set<String> = [
        "a", "an", "and", "am", "as", "at", "auf", "der", "die", "das",
        "für", "gegen", "im", "in", "mit", "nach", "of", "ohne", "on", "the",
        "to", "und", "von", "with", "zu"
    ]

    private static let initialEquipmentWords: Set<String> = [
        "bar", "barbell", "band", "bands", "bodyweight", "cable", "dumbbell",
        "ez", "kettlebell", "machine", "resistance", "smith", "t", "tbar"
    ]

    private static let initialMovementWords: Set<String> = [
        "back", "bike", "bridge", "carry", "clean", "climber", "crossover", "crunch",
        "curl", "cycling", "deadlift", "dip", "down", "ergometer", "extension", "fly",
        "heben", "hold", "jog", "kickback", "kniebeuge", "kreuzheben", "leg", "lunge",
        "plank", "press", "pull", "pulldown", "push", "raise", "radfahren", "row",
        "rudern", "run", "seilspringen", "shrug", "squat", "strecken", "stütz", "swing",
        "thrust", "twist", "up", "walk", "woodchop", "wadenheben"
    ]

    var visualKind: ExerciseVisualKind {
        let key = nameKey.lowercased()
        let names = "\(englishName) \(germanName)".lowercased()
        let value = "\(key) \(names)"
        if value.contains("rowing_ergometer") || value.contains("ruderergometer") { return .rowing }
        if value.contains("bike") || value.contains("ergometer") || value.contains("elliptical") || value.contains("crosstrainer") { return .cycle }
        if value.contains("run") || value.contains("lauf") || value.contains("stairclimber") || value.contains("treppensteiger") { return .run }
        if value.contains("jump") || value.contains("seilspring") || value.contains("mountain_climber") { return .jump }
        if equipment == .kettlebell || value.contains("kettlebell") { return .kettlebell }
        if value.contains("back_extension") || value.contains("hyperextension") || value.contains("good morning") || value.contains("goodmorning") || value.contains("nordic") { return .hinge }
        if value.contains("leg_raise") || value.contains("beinheben") || value.contains("abwheel") || value.contains("ab-wheel") { return .core }
        if value.contains("dip") { return .press }
        if equipment == .machine && !Set(primaryMuscles).isDisjoint(with: ["quadriceps", "hamstrings", "glutes", "calves"]) { return .squat }
        if value.contains("squat") || value.contains("kniebeuge") || value.contains("leg_press") || value.contains("beinpresse") || value.contains("leg_extension") || value.contains("beinstrecker") || value.contains("leg_curl") || value.contains("beinbeuger") || value.contains("calf_raise") || value.contains("wadenheben") { return .squat }
        if value.contains("deadlift") || value.contains("kreuzheben") || value.contains("rdl") || value.contains("hip_thrust") || value.contains("glute_bridge") { return .hinge }
        if value.contains("lunge") || value.contains("ausfallschritt") { return .lunge }
        if value.contains("row") || value.contains("ruder") { return .row }
        if value.contains("pull_up") || value.contains("klimmzug") || value.contains("pulldown") || value.contains("latzug") { return .pull }
        if value.contains("curl") { return .curl }
        if value.contains("raise") || value.contains("heben") || value.contains("face_pull") { return .raise }
        if value.contains("press") || value.contains("drücken") || value.contains("push_up") || value.contains("liegestütz") { return .press }
        if value.contains("plank") || primaryMuscles.contains("core") { return .core }
        return .generic
    }

    static let builtIns: [TrainingExercise] = [
        .builtIn("barbell_bench_press", "Barbell Bench Press", "Langhantel-Bankdrücken", .weightReps, .barbell, ["chest"], ["triceps", "front_shoulders"]),
        .builtIn("barbell_back_squat", "Barbell Back Squat", "Langhantel-Kniebeuge", .weightReps, .barbell, ["quadriceps", "glutes"], ["hamstrings", "core"]),
        .builtIn("conventional_deadlift", "Conventional Deadlift", "Klassisches Kreuzheben", .weightReps, .barbell, ["hamstrings", "glutes", "back"], ["core", "forearms"]),
        .builtIn("overhead_press", "Overhead Press", "Schulterdrücken", .weightReps, .barbell, ["front_shoulders", "shoulders"], ["triceps", "core"]),
        .builtIn("pull_up", "Pull-Up", "Klimmzug", .bodyweight, .bodyweight, ["lats", "back"], ["biceps", "forearms"]),
        .builtIn("dumbbell_row", "Dumbbell Row", "Kurzhantel-Rudern", .weightReps, .dumbbell, ["upper_back", "lats"], ["biceps", "rear_shoulders"]),
        .builtIn("lat_pulldown", "Lat Pulldown", "Latzug", .weightReps, .cable, ["lats"], ["biceps", "back"]),
        .builtIn("leg_press", "Leg Press", "Beinpresse", .weightReps, .machine, ["quadriceps", "glutes"], ["hamstrings"]),
        .builtIn("push_up", "Push-Up", "Liegestütz", .repsOnly, .bodyweight, ["chest"], ["triceps", "shoulders"]),
        .builtIn("plank", "Plank", "Unterarmstütz", .duration, .bodyweight, ["core"], ["shoulders"]),
        .builtIn("treadmill_run", "Treadmill Run", "Laufband", .distanceDuration, .cardio, ["cardio", "quadriceps", "hamstrings", "glutes", "calves"], []),
        .builtIn("band_face_pull", "Band Face Pull", "Band Face Pull", .weightReps, .bands, ["rear_shoulders", "upper_back"], ["biceps"]),
        .builtIn("incline_dumbbell_press", "Incline Dumbbell Press", "Schrägbankdrücken mit Kurzhanteln", .weightReps, .dumbbell, ["chest"], ["triceps", "front_shoulders"]),
        .builtIn("lateral_raise", "Lateral Raise", "Seitheben", .weightReps, .dumbbell, ["shoulders"], []),
        .builtIn("biceps_curl", "Biceps Curl", "Bizepscurls", .weightReps, .dumbbell, ["biceps"], ["forearms"]),
        .builtIn("triceps_pushdown", "Triceps Pushdown", "Trizepsdrücken am Kabelzug", .weightReps, .cable, ["triceps"], []),
        .builtIn("standing_calf_raise", "Standing Calf Raise", "Wadenheben stehend", .weightReps, .machine, ["calves"], []),
        .builtIn("barbell_row", "Barbell Row", "Langhantel-Rudern", .weightReps, .barbell, ["upper_back", "lats"], ["biceps", "forearms", "rear_shoulders"]),
        .builtIn("romanian_deadlift", "Romanian Deadlift", "Rumänisches Kreuzheben", .weightReps, .barbell, ["hamstrings", "glutes"], ["back", "core"]),
        .builtIn("hip_thrust", "Hip Thrust", "Hip Thrust", .weightReps, .barbell, ["glutes"], ["hamstrings", "core"]),
        .builtIn("cable_glute_kickback", "Cable Glute Kickback", "Glute Kickback am Kabelturm", .weightReps, .cable, ["glutes"], ["hamstrings"]),
        .builtIn("leg_extension", "Leg Extension", "Beinstrecker-Maschine", .weightReps, .machine, ["quadriceps"], []),
        .builtIn("chest_fly_machine", "Chest Fly Machine", "Butterfly-Maschine", .weightReps, .machine, ["chest"], ["front_shoulders"]),
        .builtIn("seated_cable_row", "Seated Cable Row", "Sitzendes Kabelrudern", .weightReps, .cable, ["upper_back", "lats"], ["biceps", "rear_shoulders"]),
        .builtIn("dumbbell_shoulder_press", "Dumbbell Shoulder Press", "Kurzhantel-Schulterdrücken", .weightReps, .dumbbell, ["front_shoulders", "shoulders"], ["triceps"]),
        .builtIn("dumbbell_rdl", "Dumbbell Romanian Deadlift", "Rumänisches Kreuzheben mit Kurzhanteln", .weightReps, .dumbbell, ["hamstrings", "glutes"], ["back"]),
        .builtIn("goblet_squat", "Goblet Squat", "Goblet Squat", .weightReps, .dumbbell, ["quadriceps", "glutes"], ["core"]),
        .builtIn("hammer_curl", "Hammer Curl", "Hammercurls", .weightReps, .dumbbell, ["biceps"], ["forearms"]),
        .builtIn("bodyweight_squat", "Bodyweight Squat", "Kniebeuge ohne Gewicht", .repsOnly, .bodyweight, ["quadriceps", "glutes"], ["hamstrings"]),
        .builtIn("reverse_lunge", "Reverse Lunge", "Ausfallschritt rückwärts", .repsOnly, .bodyweight, ["quadriceps", "glutes"], ["hamstrings"]),
        .builtIn("glute_bridge", "Glute Bridge", "Glute Bridge", .repsOnly, .bodyweight, ["glutes"], ["hamstrings", "core"]),
        .builtIn("pike_push_up", "Pike Push-Up", "Pike-Liegestütz", .repsOnly, .bodyweight, ["front_shoulders", "shoulders"], ["triceps", "core"]),
        .builtIn("mountain_climber", "Mountain Climber", "Mountain Climber", .duration, .bodyweight, ["core", "cardio"], ["shoulders", "legs"]),
        .builtIn("band_squat", "Resistance Band Squat", "Kniebeuge mit Widerstandsband", .weightReps, .bands, ["quadriceps", "glutes"], ["hamstrings"]),
        .builtIn("band_row", "Resistance Band Row", "Rudern mit Widerstandsband", .weightReps, .bands, ["upper_back", "lats"], ["biceps", "rear_shoulders"]),
        .builtIn("band_chest_press", "Resistance Band Chest Press", "Brustdrücken mit Widerstandsband", .weightReps, .bands, ["chest"], ["triceps"]),
        .builtIn("band_rdl", "Resistance Band Romanian Deadlift", "Rumänisches Kreuzheben mit Widerstandsband", .weightReps, .bands, ["hamstrings", "glutes"], ["back"]),
        .builtIn("band_lateral_raise", "Resistance Band Lateral Raise", "Seitheben mit Widerstandsband", .weightReps, .bands, ["shoulders"], []),
        .builtIn("kettlebell_swing", "Kettlebell Swing", "Kettlebell Swing", .weightReps, .kettlebell, ["glutes", "hamstrings"], ["back", "core"]),
        .builtIn("kettlebell_goblet", "Kettlebell Goblet Squat", "Kettlebell Goblet Squat", .weightReps, .kettlebell, ["quadriceps", "glutes"], ["core"]),
        .builtIn("kettlebell_press", "Kettlebell Clean & Press", "Kettlebell Clean & Press", .weightReps, .kettlebell, ["front_shoulders", "shoulders"], ["legs", "core", "triceps"]),
        .builtIn("kettlebell_row", "Kettlebell Row", "Kettlebell-Rudern", .weightReps, .kettlebell, ["upper_back", "lats"], ["biceps", "rear_shoulders"]),
        .builtIn("outdoor_run", "Outdoor Run", "Laufen im Freien", .distanceDuration, .cardio, ["cardio", "quadriceps", "hamstrings", "glutes", "calves"], []),
        .builtIn("stationary_bike", "Stationary Bike", "Ergometer", .distanceDuration, .cardio, ["cardio", "quadriceps", "hamstrings", "glutes", "calves"], []),
        .builtIn("rowing_ergometer", "Rowing Ergometer", "Ruderergometer", .distanceDuration, .cardio, ["cardio", "quadriceps", "hamstrings", "glutes", "calves", "upper_back", "lats"], ["arms", "core"]),
        .builtIn("jump_rope", "Jump Rope", "Seilspringen", .duration, .cardio, ["cardio", "calves"], ["shoulders"]),

        // Old-school bodybuilding staples.
        .builtIn("incline_barbell_press", "Incline Barbell Bench Press", "Schrägbankdrücken mit Langhantel", .weightReps, .barbell, ["chest"], ["triceps", "front_shoulders"]),
        .builtIn("decline_barbell_press", "Decline Barbell Bench Press", "Negativbankdrücken mit Langhantel", .weightReps, .barbell, ["chest"], ["triceps"]),
        .builtIn("closegrip_bench_press", "Close-Grip Bench Press", "Enges Bankdrücken", .weightReps, .barbell, ["triceps"], ["chest", "front_shoulders"]),
        .builtIn("dumbbell_chest_fly", "Dumbbell Chest Fly", "Fliegende mit Kurzhanteln", .weightReps, .dumbbell, ["chest"], ["front_shoulders"]),
        .builtIn("dumbbell_pullover", "Dumbbell Pullover", "Überzüge mit Kurzhantel", .weightReps, .dumbbell, ["lats", "chest"], ["triceps"]),
        .builtIn("arnold_shoulder_press", "Arnold Press", "Arnold Press", .weightReps, .dumbbell, ["front_shoulders", "shoulders"], ["triceps"]),
        .builtIn("upright_barbell_row", "Barbell Upright Row", "Aufrechtes Langhantelrudern", .weightReps, .barbell, ["shoulders"], ["upper_back", "biceps"]),
        .builtIn("tbar_supported_row", "T-Bar Row", "T-Bar-Rudern", .weightReps, .barbell, ["upper_back", "lats"], ["biceps", "rear_shoulders"]),
        .builtIn("barbell_shrug", "Barbell Shrug", "Schulterheben mit Langhantel", .weightReps, .barbell, ["traps"], ["forearms"]),
        .builtIn("ezbar_biceps_curl", "EZ-Bar Curl", "SZ-Curls", .weightReps, .barbell, ["biceps"], ["forearms"]),
        .builtIn("preacher_biceps_curl", "Preacher Curl", "Preacher-Curl", .weightReps, .barbell, ["biceps"], ["forearms"]),
        .builtIn("concentration_curl", "Concentration Curl", "Konzentrationscurls", .weightReps, .dumbbell, ["biceps"], ["forearms"]),
        .builtIn("reverse_barbell_curl", "Reverse Barbell Curl", "Reverse Curls mit Langhantel", .weightReps, .barbell, ["forearms"], ["biceps"]),
        .builtIn("zottman_curl", "Zottman Curl", "Zottman Curls", .weightReps, .dumbbell, ["forearms"], ["biceps"]),
        .builtIn("wrist_roller", "Wrist Roller", "Unterarm-Rolle", .weightReps, .other, ["forearms"], []),
        .builtIn("skullcrusher_ezbar", "EZ-Bar Skull Crusher", "French Press mit SZ-Stange", .weightReps, .barbell, ["triceps"], []),
        .builtIn("goodmorning_barbell", "Barbell Good Morning", "Good Mornings", .weightReps, .barbell, ["hamstrings", "glutes"], ["back", "core"]),
        .builtIn("donkey_calf_raise", "Donkey Calf Raise", "Donkey-Wadenheben", .weightReps, .machine, ["calves"], []),

        // Hypertrophy-focused cable, machine and lengthened-position options.
        .builtIn("machine_chest_press", "Machine Chest Press", "Brustpresse", .weightReps, .machine, ["chest"], ["triceps", "front_shoulders"]),
        .builtIn("machine_shoulder_press", "Machine Shoulder Press", "Schulterpresse", .weightReps, .machine, ["shoulders"], ["triceps", "front_shoulders"]),
        .builtIn("smith_incline_press", "Smith Machine Incline Press", "Schrägbankdrücken an der Multipresse", .weightReps, .machine, ["chest"], ["triceps", "front_shoulders"]),
        .builtIn("cable_fly_low_high", "Low-to-High Cable Fly", "Kabel-Fliegende von unten nach oben", .weightReps, .cable, ["chest"], ["front_shoulders"]),
        .builtIn("cable_lateral_raise", "Cable Lateral Raise", "Seitheben am Kabelzug", .weightReps, .cable, ["shoulders"], []),
        .builtIn("reverse_pecdeck_fly", "Reverse Pec Deck", "Reverse Butterfly", .weightReps, .machine, ["rear_shoulders", "upper_back"], []),
        .builtIn("supported_chest_row", "Chest-Supported Row", "Brustgestütztes Rudern", .weightReps, .machine, ["upper_back", "lats"], ["biceps", "rear_shoulders"]),
        .builtIn("onearm_cable_row", "Single-Arm Cable Row", "Einarmiges Kabelrudern", .weightReps, .cable, ["upper_back", "lats"], ["biceps"]),
        .builtIn("straightarm_pulldown", "Straight-Arm Pulldown", "Überzüge am Kabelzug", .weightReps, .cable, ["lats"], ["triceps"]),
        .builtIn("onearm_lat_pulldown", "Single-Arm Lat Pulldown", "Einarmiger Latzug", .weightReps, .cable, ["lats"], ["biceps", "back"]),
        .builtIn("assisted_pullup_machine", "Assisted Pull-Up Machine", "Unterstützte Klimmzüge an der Maschine", .weightReps, .machine, ["lats", "back"], ["biceps"]),
        .builtIn("incline_db_biceps_curl", "Incline Dumbbell Curl – Spider Curl", "Schrägbankcurls – Spider Curls", .weightReps, .dumbbell, ["biceps"], ["forearms"]),
        .builtIn("bayesian_cable_curl", "Bayesian Cable Curl", "Bayesian Curls am Kabelzug", .weightReps, .cable, ["biceps"], ["forearms"]),
        .builtIn("overhead_cable_triceps", "Overhead Cable Triceps Extension", "Überkopf-Trizepsstrecken am Kabelzug", .weightReps, .cable, ["triceps"], []),
        .builtIn("cable_triceps_kickback", "Cable Triceps Kickback", "Trizeps-Kickbacks am Kabelzug", .weightReps, .cable, ["triceps"], []),
        .builtIn("hack_squat_machine", "Hack Squat", "Hackenschmidt-Kniebeuge", .weightReps, .machine, ["quadriceps", "glutes"], ["hamstrings"]),
        .builtIn("pendulum_squat_machine", "Pendulum Squat", "Pendulum-Kniebeuge", .weightReps, .machine, ["quadriceps", "glutes"], ["hamstrings"]),
        .builtIn("smith_squat_machine", "Smith Machine Squat", "Kniebeuge an der Multipresse", .weightReps, .machine, ["quadriceps", "glutes"], ["hamstrings", "core"]),
        .builtIn("bulgarian_split_squat", "Bulgarian Split Squat", "Bulgarische Kniebeuge", .weightReps, .dumbbell, ["quadriceps", "glutes"], ["hamstrings", "core"]),
        .builtIn("walking_dumbbell_lunge", "Dumbbell Walking Lunge", "Gehende Ausfallschritte mit Kurzhanteln", .weightReps, .dumbbell, ["quadriceps", "glutes"], ["hamstrings", "core"]),
        .builtIn("seated_hamstring_curl", "Seated Leg Curl", "Beinbeuger sitzend", .weightReps, .machine, ["hamstrings"], []),
        .builtIn("lying_hamstring_curl", "Lying Leg Curl", "Beinbeuger liegend", .weightReps, .machine, ["hamstrings"], []),
        .builtIn("hip_abduction_machine", "Hip Abduction Machine", "Abduktorenmaschine", .weightReps, .machine, ["abductors"], ["glutes"]),
        .builtIn("hip_adduction_machine", "Hip Adduction Machine", "Adduktorenmaschine", .weightReps, .machine, ["adductors"], []),
        .builtIn("nordic_hamstring_curl", "Nordic Hamstring Curl", "Nordic Curl", .repsOnly, .bodyweight, ["hamstrings"], ["glutes", "core"]),
        .builtIn("back_extension_45deg", "45-Degree Back Extension", "45-Grad-Hyperextension", .weightReps, .bodyweight, ["hamstrings", "glutes"], ["back"]),
        .builtIn("seated_calf_machine", "Seated Calf Raise", "Wadenheben sitzend", .weightReps, .machine, ["calves"], []),

        // Additional compounds, core work and cardio machines.
        .builtIn("bodyweight_dip", "Dip", "Dips", .repsOnly, .bodyweight, ["chest", "triceps"], ["front_shoulders"]),
        .builtIn("weighted_dip", "Weighted Dip", "Dips mit Zusatzgewicht", .weightReps, .bodyweight, ["chest", "triceps"], ["front_shoulders"]),
        .builtIn("chinup_supinated", "Chin-Up", "Klimmzug im Untergriff", .repsOnly, .bodyweight, ["lats", "biceps"], ["back", "forearms"]),
        .builtIn("cable_ab_crunch", "Cable Crunch", "Crunch am Kabelzug", .weightReps, .cable, ["core"], []),
        .builtIn("hanging_leg_raise", "Hanging Leg Raise", "Beinheben hängend", .repsOnly, .bodyweight, ["core"], ["hip_flexors", "forearms"]),
        .builtIn("abwheel_rollout", "Ab-Wheel Rollout", "Ab-Wheel-Rollout", .repsOnly, .other, ["core"], ["shoulders"]),
        .builtIn("elliptical_trainer", "Elliptical Trainer", "Crosstrainer", .distanceDuration, .cardio, ["cardio", "quadriceps", "hamstrings", "glutes", "calves"], []),
        .builtIn("stairclimber_cardio", "Stair Climber", "Treppensteiger", .duration, .cardio, ["cardio", "quadriceps", "glutes", "calves"], []),
        .builtIn("airbike_cardio", "Air Bike", "Air Bike", .duration, .cardio, ["cardio", "quadriceps", "hamstrings", "glutes", "calves"], ["arms"])
    ] + StrengthLogDirectory.exercises + UnilateralExerciseDirectory.exercises

    /// A small set of unmistakable movement names wins over stale imported
    /// muscle metadata.  Workout logs keep a snapshot of the import data, so
    /// correcting the catalog alone would leave completed workouts rendering
    /// the wrong muscle in the body graphic.
    static func canonicalMuscleAssignment(
        englishName: String,
        germanName: String
    ) -> (primary: [String], secondary: [String])? {
        if let exercise = matchingBuiltIn(named: englishName) ?? matchingBuiltIn(named: germanName) {
            return (exercise.primaryMuscles, exercise.secondaryMuscles)
        }
        let sourceName = "\(englishName) \(germanName)"
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()

        // A leg press is a knee-extension movement. Hamstrings can assist,
        // but they must never become the blue primary region.
        if sourceName.contains("leg press") || sourceName.contains("leg_press") || sourceName.contains("beinpresse") {
            return (primary: ["quadriceps", "glutes"], secondary: ["hamstrings"])
        }
        if sourceName.contains("standing leg curl") ||
            sourceName.contains("standing hamstring curl") ||
            sourceName.contains("beinbeuger stehend") ||
            sourceName.contains("beinbeugen stehend") {
            return (primary: ["hamstrings"], secondary: [])
        }
        if sourceName.contains("adduktor") || sourceName.contains("adductor") || sourceName.contains("hip adduction") {
            return (primary: ["adductors"], secondary: [])
        }
        if sourceName.contains("abduktor") || sourceName.contains("abductor") || sourceName.contains("hip abduction") {
            return (primary: ["abductors"], secondary: ["glutes"])
        }
        if sourceName.contains("leg extension") || sourceName.contains("beinstreck") || sourceName.contains("reverse nordic") {
            return (primary: ["quadriceps"], secondary: [])
        }
        if sourceName.contains("hip flexor") || sourceName.contains("huftbeuger") || sourceName.contains("banded hip march") {
            return (primary: ["hip_flexors"], secondary: ["core"])
        }

        return nil
    }

    /// Repairs metadata on completed/imported workout snapshots. These logs
    /// can outlive catalog fixes, therefore their saved primary muscles must
    /// not be the source of truth for a known imported exercise.
    static func repairedMuscleAssignment(
        exerciseID: UUID,
        englishName: String,
        germanName: String,
        type: TrainingExerciseType,
        equipment: TrainingEquipment,
        primary: [String],
        secondary: [String]
    ) -> (primary: [String], secondary: [String])? {
        if let builtIn = builtIns.first(where: { $0.id == exerciseID }) {
            let canonical = (primary: builtIn.primaryMuscles, secondary: builtIn.secondaryMuscles)
            return canonical.primary == primary && canonical.secondary == secondary ? nil : canonical
        }
        if let canonical = canonicalMuscleAssignment(englishName: englishName, germanName: germanName) {
            return canonical.primary == primary && canonical.secondary == secondary ? nil : canonical
        }

        let snapshot = TrainingExercise(
            id: exerciseID,
            nameKey: "muscle_assignment_snapshot",
            englishName: englishName,
            germanName: germanName,
            descriptionKey: "",
            techniqueKey: "",
            type: type,
            equipment: equipment,
            primaryMuscles: primary,
            secondaryMuscles: secondary,
            isCustom: true,
            isFavorite: false,
            updatedAt: .distantPast
        )
        let repaired = snapshot.normalizedImportedCatalogEntry()
        guard repaired.primaryMuscles != snapshot.primaryMuscles ||
                repaired.secondaryMuscles != snapshot.secondaryMuscles else {
            return nil
        }
        return (primary: repaired.primaryMuscles, secondary: repaired.secondaryMuscles)
    }

    /// Private Hevy imports that duplicate a curated Hyse exercise. Historical
    /// workout snapshots keep their names and sets; only the duplicate catalog
    /// entry is retired so it cannot be selected again or re-uploaded.
    static let retiredImportedExerciseIDs: Set<UUID> = Set([
        "8be26295-9ba8-55d1-ab5e-8cd8b3a3ccdb", // Bankdrücken (Langhantel)
        "5412d55c-acc1-5174-a77b-e96b410093ca", // Bankdrücken (Multipresse)
        "fa923a6a-6614-5887-bfe0-182c2baad609", // Bayesian Bicep Curl
        "fe8071a1-34c1-5c17-acde-7e2bbf74a231", // Beinbeugen sitzend
        "c1f509c4-941d-5f8f-ae56-85774316afb9", // Beinpresse sitzend
        "318dc8ec-4608-5519-bd8d-6e20b52a64ef", // Beinstrecken
        "0fd28301-e44e-5e02-ab52-65064ce58464", // Bizepscurl (Kurzhantel)
        "bd0f98df-cf8f-57bb-82a7-f5604e3d63d9", // Hammer Curl (Kurzhantel)
        "075eb0e5-fc41-57b3-901e-831d0f20d8e9", // Brustpresse (Maschine)
        "bf17f39b-97a0-5e7f-a5ee-21c21dae2441", // Butterfly
        "e6fd2462-282c-53ab-b7eb-ca1661367f79", // Clavicular Fly
        "007f3e5f-2ec1-5950-9c4a-3c03ac67413a", // Crunch am Kabelzug
        "a74afebf-40e0-5fca-981f-0ec252b0b8d4", // Fliegende (Maschine)
        "dbc33263-ce54-5b8d-8425-7a7ce468fde3", // Hackenschmidt Squat (Maschine)
        "5ff10175-b66c-5630-bdda-d08ff3830e5a", // Hip Thrust (Langhantel)
        "4b7da693-83fa-5890-91a4-748d59b11722", // Hüftabduktion
        "7accd5f1-63a2-5d5e-9808-e29863a9806c", // Hüftadduktion
        "6762e23d-6f3f-58ea-ba46-89f42150c85c", // Iso-Laterales Rudern von oben (ohne Equipment)
        "0a56628d-64c1-502b-8ebe-21b55825755d", // Latzug (Kabel)
        "003821d8-5548-5849-9f03-e9b83dc5650b", // Latzug enger Griff (Kabelzug)
        "c0eed493-cf0b-52d9-bc74-ff90fc7d92c3", // Liegendes Beinbeugen (Maschine)
        "929e9a7f-bc40-52a5-8277-fa3d5db62e9f", // Preacher Curl (Langhantel)
        "8ab07db9-733f-55ac-84be-2654ed71f55e", // Reverse Fliegende (Maschine)
        "a2f7f59d-e55d-5ebc-bafd-c68698e24e6a", // Rudern am Kabel sitzend
        "123a79bc-3503-5807-8f93-278ec3213079", // Rumpfbeugen mit dem Kabel
        "19f958de-793d-557d-ae01-7bc037453ecb", // Schrägbankdrücken (Kurzhantel)
        "3ac3c588-02cb-5495-8394-c774ad89c6ff", // Schrägbankdrücken (Langhantel)
        "bd437a82-acfb-5f0e-83b7-78432b585344", // Seitheben (Kurzhantel)
        "f58cb2bd-cdde-56a5-b928-db10d237a757", // Squat (Langhantel)
        "8e62123b-d91f-58de-9fd1-d63588fe6ae4", // Wadenheben sitzend
        "91e6988d-735f-5e37-8cdb-913d2ce56059", // Kickbacks am Kabelzug
        "262f111a-08dc-5cf8-935a-10521d95e08a", // Reverse Curl (Cable)
        "038707c5-b047-55bf-9000-a21bfd1e4acd", // Trizepsdrücken
        "a70eebf5-dc4d-580a-b3b2-6ad661ce9c54", // doppelter Handgelenkscurl
        "5395ae94-c59d-51fd-9d13-1ac362221c67", // Überzüge
        "8f2b623c-b12a-56c9-80bd-46547ee4c9ab", // Handgelenkscurl hinter dem Rücken
        "7bd7751e-c253-54f7-9c6d-bf8d638ec8d9", // Handgelenkscurl sitzend
        "22a68331-8169-526d-aea2-fea6cb306cf3", // unspezifisches Knieheben
        "f829f3cb-3f37-5526-8c2e-2325df6df368", // Kniender Latzug mit Band
        "b291ac74-27ea-50cb-8a09-5fbbf1226b11" // Glute Kickback an der Maschine
    ].compactMap { UUID(uuidString: $0) })

    private static let retiredImportedExerciseNames: Set<String> = [
        "shoulder press seated machine",
        "seated shoulder press machine",
        "schulterpresse sitzend maschine"
    ]

    private static func normalizedCatalogName(_ name: String) -> String {
        name.lowercased()
            .replacingOccurrences(of: "ä", with: "ae")
            .replacingOccurrences(of: "ö", with: "oe")
            .replacingOccurrences(of: "ü", with: "ue")
            .replacingOccurrences(of: "ß", with: "ss")
            .folding(options: [.diacriticInsensitive], locale: Locale(identifier: "de_DE"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Different source catalogs sometimes name the same movement after the
    /// muscle instead of the motion. Resolve only unambiguous aliases; grip,
    /// stance, equipment and single-side variants remain separate exercises.
    private static let builtInNameAliases: [String: String] = [
        "adduktoren maschine": "hip_adduction_machine",
        "adductor machine": "hip_adduction_machine",
        "adductors machine": "hip_adduction_machine",
        "hip adduction machine": "hip_adduction_machine",
        "abduktoren maschine": "hip_abduction_machine",
        "abductor machine": "hip_abduction_machine",
        "abductors machine": "hip_abduction_machine",
        "hip abduction machine": "hip_abduction_machine",
        "reverse body weight lunge": "reverse_lunge",
        "rueckwaertiger ausfallschritt ohne zusatzgewicht": "reverse_lunge",
        "assisted pull up": "assisted_pullup_machine",
        "unterstuetzter klimmzug": "assisted_pullup_machine",
        "good morning": "goodmorning_barbell"
    ]

    private static let builtInByCatalogName: [String: TrainingExercise] = {
        var byName: [String: TrainingExercise] = [:]
        for exercise in builtIns {
            byName[normalizedCatalogName(exercise.englishName)] = exercise
            byName[normalizedCatalogName(exercise.germanName)] = exercise
        }
        let byKey = Dictionary(uniqueKeysWithValues: builtIns.map { ($0.nameKey, $0) })
        for (alias, key) in builtInNameAliases {
            if let exercise = byKey[key] { byName[alias] = exercise }
        }
        return byName
    }()

    static func matchingBuiltIn(named name: String) -> TrainingExercise? {
        let normalized = normalizedCatalogName(name)
        guard !normalized.isEmpty else { return nil }
        return builtInByCatalogName[normalized]
    }

    static func matchingCatalogExercise(named name: String, equipment: TrainingEquipment, in exercises: [TrainingExercise]) -> TrainingExercise? {
        if let builtIn = matchingBuiltIn(named: name) { return builtIn }
        let normalized = normalizedCatalogName(name)
        guard !normalized.isEmpty else { return nil }
        return exercises.first { exercise in
            exercise.isCustom &&
                (exercise.equipment == equipment || exercise.equipment == .other || equipment == .other) &&
                [exercise.englishName, exercise.germanName].contains {
                    normalizedCatalogName($0) == normalized
                }
        }
    }

    static func isRetiredImported(_ exercise: TrainingExercise) -> Bool {
        guard exercise.isCustom else { return false }
        if retiredImportedExerciseIDs.contains(exercise.id) { return true }
        let names = [exercise.englishName, exercise.germanName]
        if names.contains(where: { matchingBuiltIn(named: $0) != nil }) { return true }
        return names.contains {
            retiredImportedExerciseNames.contains(normalizedCatalogName($0))
        }
    }

    /// Hide repeated custom/imported entries from the picker without changing
    /// exercise IDs embedded in completed workouts or saved routines.
    static func catalogDeduplicated(_ exercises: [TrainingExercise]) -> [TrainingExercise] {
        var seenCustom: [(names: Set<String>, equipment: TrainingEquipment)] = []
        return exercises.filter { exercise in
            guard exercise.isCustom else { return true }
            guard !isRetiredImported(exercise) else { return false }
            let names = Set([exercise.englishName, exercise.germanName]
                .map(normalizedCatalogName)
                .filter { !$0.isEmpty })
            guard !seenCustom.contains(where: {
                !$0.names.isDisjoint(with: names) &&
                    ($0.equipment == exercise.equipment || $0.equipment == .other || exercise.equipment == .other)
            }) else { return false }
            seenCustom.append((names, exercise.equipment))
            return true
        }
    }

    /// Restores useful bilingual metadata that was lost when Hevy imports
    /// stored the visible source name in both language fields.
    func normalizedImportedCatalogEntry() -> TrainingExercise {
        guard isCustom else { return self }
        func curated(
            _ key: String,
            _ english: String,
            _ german: String,
            _ equipment: TrainingEquipment,
            _ primary: [String],
            _ secondary: [String] = [],
            type: TrainingExerciseType? = nil
        ) -> TrainingExercise {
            var value = self
            value.nameKey = key
            value.englishName = english
            value.germanName = german
            value.equipment = equipment
            value.primaryMuscles = primary
            value.secondaryMuscles = secondary
            if let type { value.type = type }
            return value
        }

        let sourceName = "\(englishName) \(germanName)"
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
        if sourceName.contains("lying neck curl") {
            return curated("lying_neck_curl", "Lying Neck Curl", "Nackencurl liegend", .other, ["neck"])
        }
        if sourceName.contains("lying neck extension") {
            return curated("lying_neck_extension", "Lying Neck Extension", "Nackenstrecken liegend", .other, ["neck"])
        }
        if sourceName.contains("standing leg curl") ||
            sourceName.contains("standing hamstring curl") ||
            sourceName.contains("beinbeuger stehend") ||
            sourceName.contains("beinbeugen stehend") {
            return curated("standing_hamstring_curl", "Standing Leg Curl", "Beinbeuger stehend", .machine, ["hamstrings"])
        }

        switch id.uuidString.lowercased() {
        case "d38132ce-5a20-5b6f-a5f8-eb1ca47ec2ad": return curated("smith_flat_bench_press", "Smith Machine Bench Press", "Bankdrücken an der Multipresse", .machine, ["chest"], ["triceps", "front_shoulders"])
        case "da285fb8-46ab-5512-8ba1-f90752669c78": return curated("captains_chair_leg_raise", "Captain's Chair Leg Raise", "Beinheben am Barren", .bodyweight, ["core"], ["hip_flexors"])
        case "c87813e1-a5db-54a1-89d2-b4f34d45d8f7": return curated("cable_biceps_curl", "Cable Biceps Curl", "Bizepscurl am Kabelturm", .cable, ["biceps"], ["forearms"])
        case "68d25bf9-843e-58af-b2de-de0dbb753659": return curated("assisted_chest_dip", "Assisted Chest Dip", "Brust-Dip, unterstützt", .machine, ["chest"], ["triceps", "front_shoulders"])
        case "2958f7b5-3ea3-56d4-ad88-c61fb94c63ea": return curated("cable_crossover", "Cable Crossover", "Cable Crossover", .cable, ["chest"], ["front_shoulders"])
        case "34cbccad-2fa4-5956-87ee-386013dd59b4": return curated("cable_woodchop_high_low", "High-to-Low Cable Woodchop", "Cable Twist von oben nach unten", .cable, ["core"], ["obliques"])
        case "42a912c5-96e4-5ffc-b173-fa16957abc52": return curated("chest_supported_y_raise", "Chest-Supported Dumbbell Y Raise", "Brustgestütztes Y-Heben mit Kurzhanteln", .dumbbell, ["rear_shoulders", "upper_back"])
        case "d81ed375-5300-5636-8008-e0c570ceec10": return curated("machine_ab_crunch", "Machine Crunch", "Crunch an der Maschine", .machine, ["core"])
        case "807cd1ba-1cde-587e-8b95-3b4fd6e80c58": return curated("stretching", "Stretching", "Dehnen", .bodyweight, ["mobility"], type: .duration)
        case "c8f85e6e-c765-59fa-80a0-b8e3f0833594": return curated("seated_dip_machine", "Seated Dip Machine", "Dip-Maschine im Sitzen", .machine, ["triceps"], ["chest"])
        case "1a467950-a985-56ab-8d2a-bdc963be101d": return curated("single_arm_reverse_cable_fly", "Single-Arm Reverse Cable Fly", "Einarmige Reverse Flys am Kabelzug", .cable, ["rear_shoulders"], ["upper_back"])
        case "b094a0ab-fd65-578f-a353-b11d9355fb71": return curated("single_leg_extension", "Single-Leg Extension", "Einbeiniges Beinstrecken", .machine, ["quadriceps"])
        case "459bdd0c-4824-5038-a820-5998731ea426": return curated("cable_face_pull", "Cable Face Pull", "Face Pull am Kabelzug", .cable, ["rear_shoulders", "upper_back"], ["biceps"])
        case "731481ff-6691-583d-914a-166fba70f7bb": return curated("band_chest_fly", "Resistance-Band Chest Fly", "Fliegende mit Band", .bands, ["chest"], ["front_shoulders"])
        case "714df1f2-9953-535f-9fb1-d465b44ca309": return curated("cable_front_raise", "Cable Front Raise", "Frontheben am Kabelzug", .cable, ["front_shoulders"])
        case "078ab9ce-e028-5d12-9c67-5b5343e9c644": return curated("cable_hammer_curl", "Cable Hammer Curl", "Hammercurl am Kabelzug", .cable, ["biceps"], ["forearms"])
        case "87ffd068-ef8f-5455-8492-a49694818c87": return curated("machine_hip_thrust", "Machine Hip Thrust", "Hip Thrust an der Maschine", .machine, ["glutes"], ["hamstrings"])
        case "f12aeb1b-3ad9-5f4f-8e12-6b134f310361": return curated("iso_lateral_high_row", "Iso-Lateral High Row Machine", "Iso-laterales Rudern von oben", .machine, ["upper_back", "lats"], ["biceps", "rear_shoulders"])
        case "c8977e1f-2271-534a-a258-924b7e67a4f0": return curated("jogging", "Jogging", "Joggen", .cardio, ["cardio", "quadriceps", "hamstrings", "glutes", "calves"], type: .duration)
        case "f2d39446-869f-5236-a6dd-c4de15289edc": return curated("kelso_shrug", "Kelso Shrug", "Kelso Shrugs", .barbell, ["upper_back"], ["rear_shoulders"])
        case "1641827e-6317-5b35-91a3-8e9bc01b82ef": return curated("weighted_pull_up", "Weighted Pull-Up", "Klimmzug mit Zusatzgewicht", .bodyweight, ["lats", "back"], ["biceps", "forearms"])
        case "7e16a3ae-e2cc-5d7b-b49f-efa53005facd": return curated("machine_preacher_curl", "Machine Preacher Curl", "Scott-Curl an der Maschine", .machine, ["biceps"], ["forearms"])
        case "f30d98f7-c98b-56a2-affd-4802670b9da4": return curated("seated_machine_row", "Seated Machine Row", "Rudern sitzend an der Maschine", .machine, ["upper_back", "lats"], ["biceps"])
        case "c31861f6-dd5d-51a0-af22-932823915746": return curated("machine_back_extension", "Machine Back Extension", "Rückenstrecken an der Maschine", .machine, ["back"], ["glutes", "hamstrings"])
        case "8b388250-d09a-5965-91b3-fcc7104ae8c7": return curated("reverse_cable_curl", "Reverse Cable Curl", "Reverse Curl am Kabelzug", .cable, ["forearms"], ["biceps"])
        case "428009ba-f069-5e1d-b215-086bcb1580b3": return curated("captains_chair_knee_raise", "Captain's Chair Knee Raise", "Knieheben am Barren", .bodyweight, ["core"])
        case "a33bdc12-a24f-56f2-862c-24c7b6fe6764": return curated("l_sit_hold", "L-Sit Hold", "L-Sit halten", .bodyweight, ["core"], ["quadriceps"])
        case "d353fcab-fb06-5622-ba17-5349e8475354": return curated("machine_lat_pulldown", "Machine Lat Pulldown", "Latzug an der Maschine", .machine, ["lats", "back"], ["biceps"])
        case "7628e487-61e4-5c73-85a4-c570ab726791": return curated("close_grip_lat_pulldown", "Close-Grip Lat Pulldown", "Latzug mit engem Griff", .cable, ["lats", "back"], ["biceps"])
        case "9a8913bc-50a1-526d-8ca6-4ec9e7a9c86b": return curated("dumbbell_preacher_curl", "Dumbbell Preacher Curls", "Scott-Curls mit Kurzhanteln", .dumbbell, ["biceps"], ["forearms"])
        case "51ac24fe-d7f8-53a3-968d-b1f92ae0b381": return curated("cycling", "Cycling", "Radfahren", .cardio, ["cardio", "quadriceps", "hamstrings", "glutes", "calves"])
        case "57db0e11-3016-5b98-b4b6-e8439dc9e5f2": return curated("single_arm_cable_lateral_raise", "Single-Arm Cable Lateral Raise", "Einarmiges Seitheben am Kabelturm", .cable, ["shoulders"], ["front_shoulders"])
        case "cce21e77-b0ca-56fb-822e-05cd8f2a7b45": return curated("machine_shrug", "Machine Shrug", "Schulterheben an der Maschine", .machine, ["traps"], ["forearms"])
        case "2a5c80a4-58e3-5cc7-b745-2eafb610a7b1": return curated("tibialis_raise", "Tibialis Raise", "Tibialis-Heben", .bodyweight, ["tibialis"])
        case "a148d06e-d509-5e3c-9cf1-610255065fd6": return curated("triceps_dip", "Triceps Dip", "Trizeps-Dip", .bodyweight, ["triceps"], ["chest", "front_shoulders"])
        case "6e172c9c-85d2-5bd6-8ed7-854d1ab51d0c": return curated("weighted_triceps_dip", "Weighted Triceps Dip", "Trizeps-Dip mit Zusatzgewicht", .bodyweight, ["triceps"], ["chest", "front_shoulders"])
        case "cbbd7e2f-bb57-529c-a20a-12586bd41f66": return curated("assisted_triceps_dip", "Assisted Triceps Dip", "Unterstützter Trizeps-Dip", .machine, ["triceps"], ["chest"])
        case "a4cfcc9c-3e63-5417-979b-77dc471198d9": return curated("rope_triceps_pushdown", "Rope Triceps Pushdown", "Trizepsdrücken mit Seil", .cable, ["triceps"])
        case "3e802bda-baea-5094-b4bc-44741bbdf5fa": return curated("rope_triceps_pressdown", "Rope Triceps Pressdown", "Trizeps-Pressdown mit Seil", .cable, ["triceps"])
        case "f00d0749-839f-5043-af00-8f39944d481d": return curated("overhead_triceps_extension", "Overhead Triceps Extension", "Trizepsstrecken über Kopf", .cable, ["triceps"])
        case "c14a02dc-3eef-561e-b449-c00b48e808a0": return curated("machine_calf_press", "Machine Calf Press", "Wadenpresse an der Maschine", .machine, ["calves"])
        default:
            if let canonical = Self.canonicalMuscleAssignment(englishName: englishName, germanName: germanName) {
                var value = self
                value.primaryMuscles = canonical.primary
                value.secondaryMuscles = canonical.secondary
                return value
            }
            guard primaryMuscles.isEmpty || primaryMuscles == ["other"] else { return self }
            var value = self
            value.primaryMuscles = Self.inferredMuscles(for: sourceName, equipment: equipment)
            return value
        }
    }

    private static func inferredMuscles(for name: String, equipment: TrainingEquipment) -> [String] {
        func contains(_ terms: [String]) -> Bool { terms.contains { name.contains($0) } }
        if equipment == .cardio { return ["cardio"] }
        if contains(["tibialis", "schienbein"]) { return ["tibialis"] }
        if contains(["stretch", "dehn", "mobility", "mobilitat"]) { return ["mobility"] }
        if contains(["neck", "nacken"]) { return ["neck"] }
        if contains(["calf", "waden"]) { return ["calves"] }
        if contains(["forearm", "unterarm", "wrist", "handgelenk"]) { return ["forearms"] }
        if contains(["triceps", "trizeps"]) { return ["triceps"] }
        if contains(["biceps", "bizeps"]) { return ["biceps"] }
        if contains(["adduction", "adduktor"]) { return ["adductors"] }
        if contains(["abduction", "abduktor"]) { return ["abductors", "glutes"] }
        if contains(["hip flexor", "huftbeuger", "hip march"]) { return ["hip_flexors"] }
        if contains(["reverse nordic"]) { return ["quadriceps"] }
        if contains(["leg curl", "hamstring", "beinbeuger", "beinbeugen"]) { return ["hamstrings"] }
        if contains(["reverse curl", "reverse curls", "zottman"]) { return ["forearms"] }
        if contains(["curl", "scott-curl"]) { return ["biceps"] }
        if contains(["leg extension", "beinstreck"]) { return ["quadriceps"] }
        if contains(["leg press", "beinpresse"]) { return ["quadriceps", "glutes"] }
        if contains(["hip thrust", "glute", "gesass", "po-", "kickback"]) { return ["glutes"] }
        if contains(["squat", "kniebeuge", "lunge", "ausfallschritt"]) { return ["quadriceps", "glutes"] }
        if contains(["deadlift", "kreuzheben", "good morning", "rumänisch", "rumanisch"]) { return ["hamstrings", "glutes", "back"] }
        if contains(["crunch", "plank", "sit-up", "situp", "leg raise", "beinheben", "knieheben", "woodchop", "pallof", "dead bug", "hollow hold", "side bend", "bauch", "rumpf"]) { return ["core"] }
        if contains(["back extension", "hyperextension", "ruckenstrecken"]) { return ["back", "glutes"] }
        if contains(["shrug", "schulterheben"]) { return ["traps"] }
        if contains(["face pull", "reverse fly", "reverse butterfly", "rear delt", "hintere schulter"]) { return ["rear_shoulders", "upper_back"] }
        if contains(["pullover", "uberzug", "uberzuge"]) { return ["lats", "chest"] }
        if contains(["pulldown", "latzug", "klimmzug", "pull-up", "pull up", "chin-up"]) { return ["lats", "back"] }
        if contains([" row", "row ", "rowing", "rudern"]) { return ["upper_back", "lats"] }
        if contains(["front raise", "frontheben"]) { return ["front_shoulders"] }
        if contains(["lateral raise", "seitheben", "shoulder press", "overhead press", "military press", "schulterpresse", "schulterdruck"]) { return ["shoulders"] }
        if contains(["bench press", "bankdrucken", "incline press", "brustpresse", "chest press", "chest fly", "butterfly", "cable fly", "crossover", "fliegende", "push-up", "liegestutz"]) { return ["chest"] }
        if contains(["dip"]) { return ["chest", "triceps"] }
        if contains(["run", "lauf", "jog", "cycling", "radfahren", "bike", "ergometer", "elliptical", "crosstrainer", "stair", "treppen", "jump rope", "seilspringen"]) { return ["cardio"] }
        return ["other"]
    }

    static func builtIn(_ key: String, _ en: String, _ de: String, _ type: TrainingExerciseType, _ equipment: TrainingEquipment, _ primary: [String], _ secondary: [String]) -> TrainingExercise {
        TrainingExercise(id: stableUUID(key), nameKey: key, englishName: en, germanName: de, descriptionKey: "training.exercise.\(key).description", techniqueKey: "training.exercise.\(key).technique", type: type, equipment: equipment, primaryMuscles: primary, secondaryMuscles: secondary, isCustom: false, isFavorite: false, updatedAt: .distantPast)
    }

    private static func stableUUID(_ value: String) -> UUID {
        var bytes = Array(value.utf8)
        while bytes.count < 16 { bytes += bytes }
        bytes = Array(bytes.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7], bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}

nonisolated struct TrainingSetLog: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var type: TrainingSetType = .normal
    var weightKilograms: Double = 0
    var reps: Int = 0
    var durationSeconds: Double = 0
    /// A running timer uses wall-clock time so suspension and device restarts
    /// do not stop an active duration or distance-duration set.
    var durationTimerStartedAt: Date?
    var durationTimerBaseSeconds: Double?
    var durationTimerEverStarted: Bool?
    var distanceMeters: Double = 0
    var rpe: Double?
    var assistedKilograms: Double = 0
    var completed = false
    var completedAt: Date?
    var personalRecordFlags: [String] = []
    var updatedAt = Date()
    /// Legacy first-performance markers are baselines, not records.
    var hasPersonalRecord: Bool { personalRecordFlags.contains { $0 != "first_performance" } }
    var hasRecordablePerformance: Bool {
        weightKilograms > 0 || reps > 0 || durationSeconds > 0 || distanceMeters > 0 || assistedKilograms > 0
    }
    var durationTimerRunning: Bool { durationTimerStartedAt != nil }
    func currentDuration(at date: Date = Date()) -> Double {
        guard let durationTimerStartedAt else { return durationSeconds }
        return max(0, (durationTimerBaseSeconds ?? durationSeconds) + date.timeIntervalSince(durationTimerStartedAt))
    }
    mutating func startDurationTimer(at date: Date = Date()) {
        guard !durationTimerRunning else { return }
        if durationTimerEverStarted != true { durationSeconds = 0 }
        durationTimerBaseSeconds = durationSeconds
        durationTimerStartedAt = date
        durationTimerEverStarted = true
    }
    mutating func stopDurationTimer(at date: Date = Date()) {
        durationSeconds = currentDuration(at: date)
        durationTimerStartedAt = nil
        durationTimerBaseSeconds = nil
    }
    var volume: Double { completed ? max(0, weightKilograms) * Double(max(0, reps)) : 0 }
    var estimatedOneRepMaximum: Double {
        guard completed, weightKilograms > 0, reps > 0 else { return 0 }
        return weightKilograms * (1 + Double(reps) / 30)
    }
    var paceSecondsPerKilometer: Double? {
        guard completed, durationSeconds > 0, distanceMeters > 0 else { return nil }
        return durationSeconds / (distanceMeters / 1_000)
    }

    /// Keeps fields that do not belong to the exercise type out of a set.
    /// In particular, time-based exercises must never carry a weight or reps.
    func normalized(for exerciseType: TrainingExerciseType) -> TrainingSetLog {
        var value = self
        switch exerciseType {
        case .weightReps:
            value.stopDurationTimer()
            value.durationSeconds = 0
            value.distanceMeters = 0
            value.assistedKilograms = 0
        case .bodyweight:
            value.stopDurationTimer()
            value.durationSeconds = 0
            value.distanceMeters = 0
        case .duration:
            value.weightKilograms = 0
            value.reps = 0
            value.distanceMeters = 0
            value.assistedKilograms = 0
        case .distanceDuration:
            value.weightKilograms = 0
            value.reps = 0
            value.assistedKilograms = 0
        case .repsOnly:
            value.stopDurationTimer()
            value.weightKilograms = 0
            value.durationSeconds = 0
            value.distanceMeters = 0
            value.assistedKilograms = 0
        }
        return value
    }
}

nonisolated struct ExerciseProgressGoal: Codable, Equatable, Sendable {
    var minimumRepetitions: Int
    var maximumRepetitions: Int
    var weightIncrementKilograms: Double

    init(minimumRepetitions: Int = 8, maximumRepetitions: Int = 10, weightIncrementKilograms: Double = 2.5) {
        self.minimumRepetitions = max(1, minimumRepetitions)
        self.maximumRepetitions = max(self.minimumRepetitions, maximumRepetitions)
        self.weightIncrementKilograms = max(0, weightIncrementKilograms)
    }
}

nonisolated struct TrainingPersonalRecordFeedback: Identifiable, Equatable, Sendable {
    let id = UUID()
    let flags: [String]
    let exerciseName: String
    let exerciseGermanName: String
    let weightKilograms: Double
    let repetitions: Int
    let setVolume: Double
    let estimatedOneRepMaximum: Double

    func exerciseDisplayName(isGerman: Bool) -> String {
        isGerman && !exerciseGermanName.isEmpty ? exerciseGermanName : exerciseName
    }
}

nonisolated struct WorkoutExerciseLog: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var exerciseID: UUID
    var exerciseNameSnapshot: String
    var exerciseGermanNameSnapshot: String
    var exerciseTypeSnapshot: TrainingExerciseType
    var equipmentSnapshot: TrainingEquipment
    var primaryMusclesSnapshot: [String]
    var secondaryMusclesSnapshot: [String]
    var notes = ""
    var restSeconds = 90
    var supersetGroup: String?
    var sets: [TrainingSetLog] = [TrainingSetLog()]
    var isUnilateralSnapshot: Bool? = nil
    var completedSetCount: Int { sets.filter(\.completed).count }
    /// Warm-up sets are logged and shown, but they are not working sets and
    /// therefore do not count towards set statistics.
    var completedWorkingSetCount: Int { sets.filter { $0.completed && $0.type != .warmup }.count }
}

nonisolated enum TrainingPreviousPerformance {
    /// Match each placement to the same occurrence of its exercise in the last workout.
    /// WorkoutExerciseLog IDs are new for every run, so they cannot link runs directly.
    static func setsByPlacement(for current: WorkoutLog, in completedWorkouts: [WorkoutLog]) -> [UUID: [TrainingSetLog?]] {
        let candidates = completedWorkouts.filter { $0.status == .completed && $0.id != current.id }
        let sameRoutine: [WorkoutLog]
        if let routineID = current.routineID {
            sameRoutine = candidates.filter { $0.routineID == routineID }
        } else {
            sameRoutine = []
        }
        let previous: WorkoutLog?
        if let latest = sameRoutine.max(by: { ($0.completedAt ?? $0.startedAt) < ($1.completedAt ?? $1.startedAt) }) {
            previous = latest
        } else {
            let name = current.name.trimmingCharacters(in: .whitespacesAndNewlines)
            previous = candidates
                .filter { candidate in
                    (current.routineID == nil || candidate.routineID == nil)
                        && candidate.name.trimmingCharacters(in: .whitespacesAndNewlines)
                            .compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
                }
                .max(by: { ($0.completedAt ?? $0.startedAt) < ($1.completedAt ?? $1.startedAt) })
        }
        guard let previous else { return [:] }
        var previousByExercise: [UUID: [[TrainingSetLog?]]] = [:]
        for exercise in previous.exercises {
            previousByExercise[exercise.exerciseID, default: []].append(exercise.sets.filter(\.completed).map(Optional.some))
        }
        var occurrences: [UUID: Int] = [:]
        var result: [UUID: [TrainingSetLog?]] = [:]
        for exercise in current.exercises {
            let occurrence = occurrences[exercise.exerciseID, default: 0]
            occurrences[exercise.exerciseID] = occurrence + 1
            if let placements = previousByExercise[exercise.exerciseID], occurrence < placements.count {
                result[exercise.id] = placements[occurrence]
            }
        }
        return result
    }
}

nonisolated enum TrainingSetStatistics {
    static let settingKey = "countUnilateralSetsAsHalf_v1"

    static func isUnilateral(_ exercise: TrainingExercise) -> Bool {
        if let explicit = exercise.isUnilateral { return explicit }
        if unilateralExerciseIDs.contains(exercise.id) { return true }
        return isUnilateralName(exercise.englishName) || isUnilateralName(exercise.germanName)
    }

    static func isUnilateral(_ exercise: WorkoutExerciseLog) -> Bool {
        if let explicit = exercise.isUnilateralSnapshot { return explicit }
        if unilateralExerciseIDs.contains(exercise.exerciseID) { return true }
        return isUnilateralName(exercise.exerciseNameSnapshot) || isUnilateralName(exercise.exerciseGermanNameSnapshot)
    }

    static func count(_ exercise: WorkoutExerciseLog, halveUnilateral: Bool) -> Double {
        Double(exercise.completedWorkingSetCount) * (halveUnilateral && isUnilateral(exercise) ? 0.5 : 1)
    }

    static func count(_ workout: WorkoutLog, halveUnilateral: Bool) -> Double {
        workout.exercises.reduce(0) { $0 + count($1, halveUnilateral: halveUnilateral) }
    }

    static func count(_ workouts: [WorkoutLog], halveUnilateral: Bool) -> Double {
        workouts.reduce(0) { $0 + count($1, halveUnilateral: halveUnilateral) }
    }

    /// The active-workout bar uses the same weight for a planned set and its
    /// completion, so completing every set still fills the bar to 100%.
    static func progress(_ workout: WorkoutLog) -> Double {
        let weights = workout.exercises.map { exercise -> (completed: Double, total: Double) in
            let weight = isUnilateral(exercise) ? 0.5 : 1.0
            return (Double(exercise.completedSetCount) * weight, Double(exercise.sets.count) * weight)
        }
        let total = weights.reduce(0.0) { $0 + $1.total }
        guard total > 0 else { return 0 }
        return weights.reduce(0.0) { $0 + $1.completed } / total
    }

    static func formatted(_ count: Double, locale: Locale) -> String {
        count.formatted(.number.precision(.fractionLength(0...2)).locale(locale))
    }

    private static let unilateralExerciseIDs = Set(TrainingExercise.builtIns.filter {
        $0.nameKey.hasPrefix("uni_") || isUnilateralName($0.englishName) || isUnilateralName($0.germanName)
            || ["onearm_cable_row", "onearm_lat_pulldown", "bulgarian_split_squat"].contains($0.nameKey)
    }.map(\.id))

    private static func isUnilateralName(_ name: String) -> Bool {
        let normalized = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        let terms = [
            "unilateral", "einseitig", "single-arm", "single arm", "single-leg", "single leg",
            "one-arm", "one arm", "one-leg", "one leg", "one-handed", "one handed",
            "1-arm", "1 arm", "1-leg", "1 leg", "einarm", "einbein", "pistol squat",
            "split squat", "bulgarian squat", "bulgarische kniebeuge"
        ]
        return terms.contains { normalized.contains($0) }
    }
}

nonisolated enum WorkoutStatus: String, Codable, Sendable { case active, paused, completed }

nonisolated struct WorkoutLog: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var remoteID: String?
    var routineID: UUID?
    var name: String
    var status: WorkoutStatus = .active
    var startedAt = Date()
    var completedAt: Date?
    var pausedAt: Date?
    var accumulatedPausedSeconds: TimeInterval?
    var timezone = TimeZone.autoupdatingCurrent.identifier
    var notes = ""
    var gymName: String?
    var gymAddress: String?
    var gymLatitude: Double?
    var gymLongitude: Double?
    var visibility: String?
    var mediaLocalFilename: String?
    var exercises: [WorkoutExerciseLog] = []
    var updatedAt = Date()
    var syncError: Bool = false

    var completedSets: [TrainingSetLog] { exercises.flatMap(\.sets).filter(\.completed) }
    var totalVolume: Double { completedSets.reduce(0) { $0 + $1.volume } }
    var totalReps: Int { completedSets.reduce(0) { $0 + max(0, $1.reps) } }
    var duration: TimeInterval {
        let end = completedAt ?? pausedAt ?? Date()
        return max(0, end.timeIntervalSince(startedAt) - (accumulatedPausedSeconds ?? 0))
    }
    var muscleGroups: [String] { Array(Set(exercises.flatMap(\.primaryMusclesSnapshot))).sorted() }
    var gymSelectionID: String? {
        guard let gymName, let gymLatitude, let gymLongitude else { return nil }
        return "\(gymName)|\(gymLatitude)|\(gymLongitude)"
    }
}

nonisolated enum TrainingWorkoutRecovery {
    static func restoredWorkouts(
        from stored: [WorkoutLog],
        journal: WorkoutLog?,
        completedCheckpoint: WorkoutLog?,
        completionReceipts: [UUID: Date] = [:]
    ) -> [WorkoutLog] {
        var restored = stored
        if let journal, journal.status == .active || journal.status == .paused {
            if let index = restored.firstIndex(where: { $0.id == journal.id }) {
                if restored[index].status != .completed && restored[index].updatedAt < journal.updatedAt {
                    restored[index] = journal
                }
            } else {
                restored.append(journal)
            }
        }
        if let completedCheckpoint, completedCheckpoint.status == .completed {
            if let index = restored.firstIndex(where: { $0.id == completedCheckpoint.id }) {
                if restored[index].status != .completed || restored[index].updatedAt < completedCheckpoint.updatedAt {
                    restored[index] = completedCheckpoint
                }
            } else {
                restored.append(completedCheckpoint)
            }
        }
        return restored.map { applyingCompletionReceipt(to: $0, completedAt: completionReceipts[$0.id]) }
    }

    static func applyingCompletionReceipt(to workout: WorkoutLog, completedAt: Date?) -> WorkoutLog {
        guard let completedAt, workout.status != .completed else { return workout }
        var completed = workout
        completed.status = .completed
        completed.completedAt = completedAt
        completed.pausedAt = nil
        completed.updatedAt = max(workout.updatedAt, completedAt)
        return completed
    }

    static func shouldKeepCurrent(_ current: WorkoutLog, over incoming: WorkoutLog?, incomingWasActive: Bool = false) -> Bool {
        (incomingWasActive && current.status == .completed)
            || current.updatedAt > (incoming?.updatedAt ?? .distantPast)
            || (current.status == .completed && incoming?.status != .completed)
    }
}

nonisolated struct BodyMeasurement: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var date: Date
    var weightKilograms: Double?
    var bodyFatPercentage: Double?
    var centimeters: [String: Double]
    var source: String
    var updatedAt: Date
}

nonisolated struct HevyImportFile: Sendable {
    let name: String
    let data: Data
}

nonisolated struct ParsedHevyImport: Sendable {
    let workouts: [WorkoutLog]
    let routines: [WorkoutRoutine]
    let customExercises: [TrainingExercise]
    let measurements: [BodyMeasurement]
    let ignoredRows: Int
}

nonisolated struct HevyImportSummary: Sendable {
    let importedWorkouts: Int
    let skippedWorkouts: Int
    let importedRoutines: Int
    let skippedRoutines: Int
    let importedExercises: Int
    let importedMeasurements: Int
    let skippedMeasurements: Int
    let ignoredRows: Int
}

nonisolated struct RoutineExercise: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var exercise: TrainingExercise
    var notes = ""
    var restSeconds = 90
    var supersetGroup: String?
    var sets: [TrainingSetLog] = [TrainingSetLog()]
    /// When the user last edited this note in the routine itself. Local only
    /// (optional, so older snapshots decode); unrelated routine changes such
    /// as reordering or syncing must not replace notes from the last workout.
    var notesUpdatedAt: Date?
}

nonisolated struct WorkoutRoutine: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var remoteID: String?
    var name: String
    var details = ""
    var folder = ""
    var plannedWeekday: Int?
    var sortOrder: Int?
    var exercises: [RoutineExercise] = []
    var updatedAt = Date()
    var imageFileName: String?
    /// Small synchronized preview; the full image stays in the local image store and public share.
    var imageData: Data?
    var shareRecordID: String?
}

nonisolated enum TrainingExerciseNoteHistory {
    /// An exercise can appear more than once in a routine. Match its position
    /// among identical exercises instead of reusing the last matching note.
    static func notes(
        for placement: RoutineExercise,
        occurrence: Int,
        in routine: WorkoutRoutine,
        completedWorkouts: [WorkoutLog],
        useRecentNotes: Bool
    ) -> String {
        guard useRecentNotes else { return placement.notes }
        if let recent = latest(
            exerciseID: placement.exercise.id,
            occurrence: occurrence,
            routine: routine,
            in: completedWorkouts
        ) {
            // A later edit of this note in the routine wins, including an
            // intentionally empty one. Other routine changes do not count.
            if let edited = placement.notesUpdatedAt {
                return edited > recent.startedAt ? placement.notes : recent.notes
            }
            return recent.notes.isEmpty ? placement.notes : recent.notes
        }
        guard placement.notes.isEmpty else { return placement.notes }
        return latest(exerciseID: placement.exercise.id, occurrence: occurrence, in: completedWorkouts)?.notes ?? ""
    }

    /// `completedWorkouts` is supplied newest first by TrainingStore.
    static func latest(
        exerciseID: UUID,
        occurrence: Int? = nil,
        routine: WorkoutRoutine? = nil,
        in completedWorkouts: [WorkoutLog]
    ) -> (notes: String, startedAt: Date)? {
        for workout in completedWorkouts where workout.status == .completed {
            if let routine,
               workout.routineID != routine.id && !(workout.routineID == nil && workout.name == routine.name) {
                continue
            }
            let matches = workout.exercises.filter { $0.exerciseID == exerciseID }
            let match: WorkoutExerciseLog?
            if let occurrence {
                match = matches.indices.contains(occurrence) ? matches[occurrence] : nil
            } else {
                match = matches.last
            }
            if let match { return (match.notes, workout.startedAt) }
        }
        return nil
    }
}

nonisolated struct RoutineWorkoutChanges: Equatable, Sendable {
    var addedExercises = 0
    var removedExercises = 0
    var addedSets = 0
    var removedSets = 0
    var changedSets = 0
    var changedExerciseSettings = 0
    var exercisesReordered = false

    init(routine: WorkoutRoutine, workout: WorkoutLog) {
        var matchedRoutineIndices = Set<Int>()
        var matchedOrder: [Int] = []
        for workoutExercise in workout.exercises {
            guard let match = routine.exercises.indices.first(where: {
                !matchedRoutineIndices.contains($0) && routine.exercises[$0].exercise.id == workoutExercise.exerciseID
            }) else {
                addedExercises += 1
                continue
            }
            matchedRoutineIndices.insert(match)
            matchedOrder.append(match)
            let routineExercise = routine.exercises[match]
            if workoutExercise.sets.count > routineExercise.sets.count {
                addedSets += workoutExercise.sets.count - routineExercise.sets.count
            } else {
                removedSets += routineExercise.sets.count - workoutExercise.sets.count
            }
            if routineExercise.sets.count == workoutExercise.sets.count {
                changedSets += zip(routineExercise.sets, workoutExercise.sets).filter { original, current in
                    original.type != current.type
                        || original.weightKilograms != current.weightKilograms
                        || original.reps != current.reps
                        || original.durationSeconds != current.durationSeconds
                        || original.distanceMeters != current.distanceMeters
                        || original.rpe != current.rpe
                        || original.assistedKilograms != current.assistedKilograms
                }.count
            }
            if routineExercise.notes != workoutExercise.notes
                || routineExercise.restSeconds != workoutExercise.restSeconds
                || routineExercise.supersetGroup != workoutExercise.supersetGroup
                || routineExercise.exercise.isUnilateral != workoutExercise.isUnilateralSnapshot {
                changedExerciseSettings += 1
            }
        }
        removedExercises = routine.exercises.count - matchedRoutineIndices.count
        exercisesReordered = matchedOrder != matchedOrder.sorted()
    }

    var hasChanges: Bool {
        addedExercises > 0 || removedExercises > 0 || addedSets > 0 || removedSets > 0
            || changedSets > 0 || changedExerciseSettings > 0 || exercisesReordered
    }
}

nonisolated enum SuggestedRoutineStyle: String, CaseIterable, Identifiable, Hashable, Sendable {
    case oldSchool = "old_school"
    case scienceBased = "science_based"
    case general
    case endurance
    case womenFocus = "women_focus"

    var id: String { rawValue }
    var localizationKey: String { "training.routines.style.\(rawValue)" }
}

nonisolated enum RoutineEquipmentFilter: String, CaseIterable, Identifiable, Hashable, Sendable {
    case bodyweight, dumbbell, bands, kettlebell, gymMachines = "gym_machines", barbell, cardio

    var id: String { rawValue }
    var localizationKey: String { "training.routines.equipment.\(rawValue)" }

    func matches(_ equipment: Set<TrainingEquipment>) -> Bool {
        guard !equipment.isEmpty else { return false }
        switch self {
        case .bodyweight:
            return equipment.isSubset(of: [.bodyweight])
        case .dumbbell:
            return equipment.isSubset(of: [.dumbbell, .bodyweight]) && equipment.contains(.dumbbell)
        case .bands:
            return equipment.isSubset(of: [.bands, .bodyweight]) && equipment.contains(.bands)
        case .kettlebell:
            return equipment.isSubset(of: [.kettlebell, .bodyweight]) && equipment.contains(.kettlebell)
        case .gymMachines:
            return equipment.isSubset(of: [.machine, .cable, .bodyweight, .cardio]) && !equipment.isDisjoint(with: [.machine, .cable])
        case .barbell:
            return equipment.isSubset(of: [.barbell, .bodyweight]) && equipment.contains(.barbell)
        case .cardio:
            return equipment.contains(.cardio)
        }
    }
}

nonisolated struct SuggestedRoutineProgram: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let summary: String
    let daysPerWeek: Int
    let style: SuggestedRoutineStyle
    let routines: [WorkoutRoutine]

    var equipment: Set<TrainingEquipment> {
        Set(routines.flatMap(\.exercises).map(\.exercise.equipment))
    }

    static func library(isGerman: Bool) -> [SuggestedRoutineProgram] {
        let exercises = Dictionary(uniqueKeysWithValues: TrainingExercise.builtIns.map { ($0.nameKey, $0) })
        func coachingNote(_ key: String) -> String {
            let text: (de: String, en: String)
            switch key {
            case "barbell_back_squat": text = ("Spanne Rumpf und oberen Rücken an. Steigere das Gewicht erst, wenn Tiefe und Kniekontrolle stabil bleiben.", "Brace your core and upper back. Add weight only while depth and knee control stay consistent.")
            case "barbell_bench_press": text = ("Schulterblätter nach hinten unten ziehen und kontrolliert absenken. Die Übung baut Brust- und Trizepskraft auf.", "Pull your shoulder blades back and down, then lower with control. This builds chest and triceps strength.")
            case "incline_dumbbell_press": text = ("Nutze eine moderate Schräglage und führe die Hanteln kontrolliert. Der Winkel betont die obere Brust.", "Use a moderate incline and control the dumbbells. This angle emphasizes the upper chest.")
            case "overhead_press", "dumbbell_shoulder_press": text = ("Gesäß und Rumpf fest halten, ohne ins Hohlkreuz auszuweichen. Die Übung trainiert besonders die vordere Schulter.", "Keep glutes and core tight without leaning back. This exercise especially trains the front delts.")
            case "lateral_raise", "band_lateral_raise": text = ("Mit leicht gebeugten Armen bis etwa Schulterhöhe heben. Weniger Gewicht und saubere Kontrolle treffen die seitliche Schulter besser.", "Raise with slightly bent arms to about shoulder height. Less load and clean control target the side delts better.")
            case "triceps_pushdown": text = ("Ellbogen am Körper lassen und unten vollständig strecken. So arbeitet der Trizeps statt Schulter und Oberkörper.", "Keep elbows by your sides and fully extend at the bottom. This keeps the work on your triceps.")
            case "push_up", "band_chest_press": text = ("Körper stabil halten und den vollen Bewegungsweg nutzen. Steigere zuerst Wiederholungen, danach den Widerstand.", "Keep your body stable and use a full range of motion. Add repetitions first, then resistance.")
            case "pike_push_up": text = ("Hüfte hoch halten und den Kopf kontrolliert zwischen den Händen absenken. Das ist die Körpergewichts-Variante für Schulterkraft.", "Keep your hips high and lower your head between your hands with control. This is a bodyweight shoulder-strength movement.")
            case "chest_fly_machine": text = ("Brust geöffnet lassen und die Arme in einem Bogen zusammenführen. Nicht aus den Schultern nach vorn drücken.", "Keep your chest open and bring your arms together in an arc. Avoid rolling the shoulders forward.")
            case "conventional_deadlift": text = ("Latissimus anspannen und die Stange nah am Körper führen. Saubere Wiederholungen sind wichtiger als schnelles Zusatzgewicht.", "Engage your lats and keep the bar close. Clean repetitions matter more than adding weight quickly.")
            case "romanian_deadlift", "dumbbell_rdl", "band_rdl": text = ("Hüfte nach hinten schieben und Rücken neutral halten. Stoppe, sobald die hintere Oberschenkelmuskulatur deutlich spannt.", "Push your hips back and keep a neutral spine. Stop when you feel a strong hamstring stretch.")
            case "barbell_row", "dumbbell_row", "kettlebell_row": text = ("Aus dem Ellbogen ziehen und den Oberkörper ruhig halten. Die Übung gibt dem Rücken Dicke und trainiert die Schulterblattkontrolle.", "Drive through the elbow and keep your torso still. This builds back thickness and shoulder-blade control.")
            case "seated_cable_row", "band_row": text = ("Zuerst die Schulterblätter zurückführen, dann die Ellbogen ziehen. Nicht mit Schwung nach hinten lehnen.", "Move the shoulder blades back first, then pull with the elbows. Avoid leaning back for momentum.")
            case "pull_up", "lat_pulldown": text = ("Brust leicht anheben und Ellbogen Richtung Hüfte ziehen. Steigere Wiederholungen oder Gewicht bei gleichbleibendem Bewegungsweg.", "Lift your chest slightly and pull your elbows toward your hips. Progress reps or load while keeping the same range.")
            case "band_face_pull": text = ("Zum Gesicht ziehen und die Hände am Ende auseinanderführen. Das stärkt hintere Schulter und Schulterblattkontrolle.", "Pull toward your face and separate your hands at the end. This strengthens rear delts and shoulder-blade control.")
            case "biceps_curl": text = ("Ellbogen ruhig halten und vollständig strecken. Kontrollierte Wiederholungen belasten den Bizeps besser als Schwung.", "Keep elbows still and reach full extension. Controlled reps load the biceps better than momentum.")
            case "hammer_curl": text = ("Handflächen zueinander lassen und ohne Schwung curlen. Der neutrale Griff trainiert zusätzlich Unterarm und Brachialis.", "Keep palms facing each other and curl without swinging. The neutral grip also trains forearms and brachialis.")
            case "leg_press": text = ("Unteren Rücken am Polster lassen und Knie kontrolliert beugen. Nutze den sicheren Bewegungsweg für zusätzliches Beinvolumen.", "Keep your lower back on the pad and bend the knees with control. Use a safe range for extra leg volume.")
            case "leg_extension": text = ("Oberschenkel ruhig halten und oben kurz anspannen. Die Übung isoliert den Quadrizeps nach den Grundübungen.", "Keep your thighs still and squeeze briefly at the top. This isolates the quads after compound work.")
            case "lying_hamstring_curl": text = ("Hüfte am Polster halten und die Fersen kontrolliert zum Gesäß führen. Das Polster bleibt knapp oberhalb der Fersen.", "Keep your hips on the pad and curl your heels toward your glutes with control. Keep the roller just above your heels.")
            case "standing_calf_raise": text = ("Unten kurz dehnen, oben vollständig auf die Zehenspitzen drücken. Nicht aus den Knien wippen.", "Pause in the stretch, then rise fully onto your toes. Avoid bouncing through the knees.")
            case "goblet_squat", "kettlebell_goblet": text = ("Gewicht nah an der Brust halten und zwischen die Hüften setzen. Ideal, um eine stabile Kniebeuge zu üben.", "Hold the weight close to your chest and sit between your hips. Ideal for practising a stable squat.")
            case "bodyweight_squat", "band_squat": text = ("Knie in Richtung der Zehen führen und kontrolliert aufstehen. Erhöhe Wiederholungen oder Bandwiderstand schrittweise.", "Track knees toward the toes and stand up with control. Increase reps or band resistance gradually.")
            case "reverse_lunge": text = ("Weit genug zurücksteigen und über den vorderen Fuß hochdrücken. Einbeinige Arbeit verbessert Kraft und Stabilität.", "Step back far enough and drive through the front foot. Unilateral work improves strength and stability.")
            case "hip_thrust", "glute_bridge": text = ("Becken kontrolliert strecken und oben das Gesäß anspannen, ohne den Rücken zu überstrecken. Fokus: Gesäßkraft.", "Extend the hips with control and squeeze the glutes without overextending your back. Focus: glute strength.")
            case "plank": text = ("Rippen zum Becken ziehen und gleichmäßig atmen. Beende den Satz, bevor die Hüfte absinkt oder der Rücken ausweicht.", "Pull ribs toward pelvis and breathe steadily. End the set before your hips sag or your back compensates.")
            case "mountain_climber": text = ("Rumpf ruhig halten und die Knie zügig nach vorn führen. Tempo nur erhöhen, solange die Position stabil bleibt.", "Keep your torso steady and drive the knees forward. Increase speed only while your position stays stable.")
            case "kettlebell_press": text = ("Handgelenk über dem Ellbogen halten und den Rumpf nicht seitlich kippen. Baut einseitige Schulter- und Rumpfkraft auf.", "Keep wrist stacked over elbow and avoid leaning sideways. This builds unilateral shoulder and core strength.")
            case "kettlebell_swing": text = ("Explosiv aus der Hüfte strecken, nicht mit den Armen heben. Stoppe, wenn die Hüftbewegung oder Rückenposition nachlässt.", "Extend explosively through the hips instead of lifting with the arms. Stop when hip drive or back position fades.")
            case "outdoor_run": text = ("Laufe locker genug, um kurze Sätze sprechen zu können. Steigere den Wochenumfang langsam, ungefähr fünf bis zehn Prozent.", "Run easily enough to speak in short sentences. Increase weekly volume gradually, around five to ten percent.")
            case "treadmill_run": text = ("Die schnellen Intervalle sollen fordernd, aber wiederholbar sein. Steigere zuerst einzelne Intervalle, dann Tempo oder Dauer.", "Fast intervals should be challenging but repeatable. Add intervals first, then increase pace or duration.")
            case "stationary_bike": text = ("Nutze einen gleichmäßigen, moderaten Widerstand. Die Einheit ergänzt Kondition, ohne die Gelenke stark zu belasten.", "Use a steady, moderate resistance. This adds conditioning with relatively low joint stress.")
            case "rowing_ergometer": text = ("Erst mit den Beinen drücken, dann Oberkörper und Arme einsetzen. Halte die Leistung kontrolliert statt hektisch zu ziehen.", "Drive with the legs first, then use torso and arms. Keep output controlled instead of pulling frantically.")
            case "jump_rope": text = ("Kleine Sprünge aus den Fußgelenken und lockere Schultern. Verlängere die Belastungszeit schrittweise.", "Use small ankle-driven jumps and relaxed shoulders. Increase work duration gradually.")
            case "arnold_shoulder_press": text = ("Drehe die Handflächen während des Drückens kontrolliert nach außen. Nutze einen schmerzfreien Bewegungsweg statt erzwungener Tiefe.", "Rotate the palms outward under control while pressing. Use a pain-free range instead of forcing extra depth.")
            case "dumbbell_pullover", "straightarm_pulldown": text = ("Halte die Rippen unten und führe die Oberarme in einem langen Bogen. Der Fokus liegt auf dem Latissimus in gedehnter Position.", "Keep the ribs down and move the upper arms through a long arc. Focus on loading the lats in a lengthened position.")
            case "tbar_supported_row", "supported_chest_row": text = ("Ziehe die Ellbogen nach hinten, ohne die Brust vom Polster zu lösen. So lässt sich der Rücken stabil und ohne viel Schwung belasten.", "Drive the elbows back without lifting your chest from the pad. This loads the back steadily with little momentum.")
            case "preacher_biceps_curl", "incline_db_biceps_curl", "bayesian_cable_curl": text = ("Lass den Bizeps kontrolliert in die Dehnung kommen und halte den Oberarm ruhig. Steigere erst bei sauberer voller Bewegung.", "Let the biceps reach a controlled stretch and keep the upper arm still. Progress only with a clean full range.")
            case "overhead_cable_triceps", "skullcrusher_ezbar": text = ("Bewege hauptsächlich den Ellenbogen und kontrolliere die gedehnte Position. Diese Variante betont den langen Trizepskopf.", "Move mainly at the elbow and control the stretched position. This variation emphasizes the long head of the triceps.")
            case "hack_squat_machine", "pendulum_squat_machine": text = ("Stelle die Füße so, dass die Knie frei nach vorn arbeiten können, und nutze kontrollierte Tiefe. Ideal für viel Quadrizepsarbeit bei stabilem Oberkörper.", "Set your feet so the knees can travel freely and use controlled depth. Ideal for high quad stimulus with a stable torso.")
            case "seated_hamstring_curl": text = ("Halte Hüfte und Oberschenkel am Polster und kontrolliere besonders die gestreckte Position. Der sitzende Winkel belastet die Beinbeuger lang.", "Keep hips and thighs against the pad and control the lengthened position. The seated angle loads the hamstrings at long muscle lengths.")
            case "cable_lateral_raise": text = ("Starte mit dem Kabel leicht hinter dem Körper und führe den Arm kontrolliert seitlich hoch. Die konstante Spannung eignet sich gut für die seitliche Schulter.", "Start with the cable slightly behind the body and raise the arm under control. Constant tension works well for the side delts.")
            default: text = ("Führe jede Wiederholung kontrolliert aus und steigere Belastung oder Wiederholungen erst bei stabiler Technik.", "Use controlled repetitions and increase load or reps only when technique remains stable.")
            }
            return isGerman ? text.de : text.en
        }
        func routine(_ name: String, _ keys: [String], reps: Int = 10, sets: Int = 3, rest: Int = 90) -> WorkoutRoutine {
            WorkoutRoutine(
                name: name,
                details: isGerman ? "Von Hyse zusammengestellte Trainingsroutine. Passe Gewichte, Wiederholungen und Pausen an dein Niveau an." : "A Hyse-curated routine. Adjust weights, repetitions and rest periods to your level.",
                folder: isGerman ? "Hyse Vorschläge" : "Hyse Suggestions",
                exercises: keys.compactMap { key in
                    guard let exercise = exercises[key] else { return nil }
                    return RoutineExercise(exercise: exercise, notes: coachingNote(key), restSeconds: rest, sets: (0..<sets).map { _ in TrainingSetLog(reps: reps) })
                }
            )
        }
        return [
            SuggestedRoutineProgram(
                id: "full_body_push_pull",
                title: "Full Body Push/Pull",
                summary: isGerman ? "Zwei Ganzkörpertage mit abwechselndem Druck- und Zugfokus." : "Two full-body days alternating push and pull emphasis.",
                daysPerWeek: 4,
                style: .scienceBased,
                routines: [
                    routine("Full Body Push", ["smith_incline_press", "machine_chest_press", "machine_shoulder_press", "leg_press", "leg_extension", "cable_ab_crunch"]),
                    routine("Full Body Pull", ["supported_chest_row", "lat_pulldown", "reverse_pecdeck_fly", "bayesian_cable_curl", "seated_hamstring_curl", "seated_calf_machine"])
                ]
            ),
            SuggestedRoutineProgram(
                id: "push_pull_legs",
                title: "Push Pull Legs",
                summary: isGerman ? "Klassischer Dreiersplit für Druck-, Zug- und Beintraining." : "Classic three-day split for push, pull and leg training.",
                daysPerWeek: 6,
                style: .general,
                routines: [
                    routine("Push", ["barbell_bench_press", "incline_dumbbell_press", "overhead_press", "lateral_raise", "triceps_pushdown"]),
                    routine("Pull", ["conventional_deadlift", "pull_up", "dumbbell_row", "lat_pulldown", "band_face_pull", "biceps_curl"]),
                    routine(isGerman ? "Beine" : "Legs", ["barbell_back_squat", "leg_press", "seated_hamstring_curl", "standing_calf_raise", "plank"])
                ]
            ),
            SuggestedRoutineProgram(
                id: "arnold_split",
                title: "Arnold Split",
                summary: isGerman ? "Brust und Rücken, Schultern und Arme sowie Beine in drei Einheiten." : "Chest and back, shoulders and arms, and legs across three sessions.",
                daysPerWeek: 6,
                style: .oldSchool,
                routines: [
                    routine(isGerman ? "Brust & Rücken" : "Chest & Back", ["barbell_bench_press", "pull_up", "incline_barbell_press", "tbar_supported_row", "dumbbell_pullover"]),
                    routine(isGerman ? "Schultern & Arme" : "Shoulders & Arms", ["arnold_shoulder_press", "upright_barbell_row", "preacher_biceps_curl", "skullcrusher_ezbar", "lateral_raise"]),
                    routine(isGerman ? "Beine" : "Legs", ["barbell_back_squat", "hack_squat_machine", "goodmorning_barbell", "lying_hamstring_curl", "donkey_calf_raise"])
                ]
            ),
            SuggestedRoutineProgram(
                id: "upper_lower",
                title: isGerman ? "Oberkörper/Unterkörper" : "Upper/Lower",
                summary: isGerman ? "Ausgewogener Zweiersplit, ideal für vier Trainingstage." : "Balanced two-way split, ideal for four training days.",
                daysPerWeek: 4,
                style: .scienceBased,
                routines: [
                    routine(isGerman ? "Oberkörper" : "Upper Body", ["smith_incline_press", "supported_chest_row", "machine_shoulder_press", "lat_pulldown", "cable_lateral_raise", "triceps_pushdown", "bayesian_cable_curl"]),
                    routine(isGerman ? "Unterkörper" : "Lower Body", ["hack_squat_machine", "leg_press", "leg_extension", "seated_hamstring_curl", "hip_abduction_machine", "seated_calf_machine", "cable_ab_crunch"])
                ]
            ),
            SuggestedRoutineProgram(
                id: "five_day_bodybuilding",
                title: isGerman ? "Old School 5er-Split" : "Old-School 5-Day Split",
                summary: isGerman ? "Eine Muskelgruppe pro Tag mit klassischem Bodybuilding-Volumen." : "One primary muscle group per day with classic bodybuilding volume.",
                daysPerWeek: 5,
                style: .oldSchool,
                routines: [
                    routine(isGerman ? "Brust" : "Chest", ["barbell_bench_press", "incline_barbell_press", "decline_barbell_press", "dumbbell_chest_fly", "dumbbell_pullover"], reps: 10, sets: 4),
                    routine(isGerman ? "Rücken" : "Back", ["conventional_deadlift", "tbar_supported_row", "pull_up", "lat_pulldown", "barbell_shrug"], reps: 8, sets: 4, rest: 120),
                    routine(isGerman ? "Schultern" : "Shoulders", ["overhead_press", "arnold_shoulder_press", "upright_barbell_row", "lateral_raise"], reps: 10, sets: 4),
                    routine(isGerman ? "Beine" : "Legs", ["barbell_back_squat", "hack_squat_machine", "goodmorning_barbell", "leg_extension", "lying_hamstring_curl", "donkey_calf_raise"], reps: 10, sets: 4, rest: 120),
                    routine(isGerman ? "Arme" : "Arms", ["ezbar_biceps_curl", "preacher_biceps_curl", "skullcrusher_ezbar", "closegrip_bench_press"], reps: 12, sets: 4)
                ]
            ),
            SuggestedRoutineProgram(
                id: "full_body_eod",
                title: "FBEOD",
                summary: isGerman ? "Ganzkörpertraining jeden zweiten Tag mit rotierenden Schwerpunkten und gut steuerbarer Erholung." : "Full-body training every other day with rotating emphasis and manageable recovery.",
                daysPerWeek: 4,
                style: .scienceBased,
                routines: [
                    routine("FBEOD A", ["hack_squat_machine", "machine_chest_press", "supported_chest_row", "cable_lateral_raise", "bayesian_cable_curl", "cable_ab_crunch"], reps: 8),
                    routine("FBEOD B", ["smith_squat_machine", "smith_incline_press", "onearm_lat_pulldown", "leg_extension", "overhead_cable_triceps", "seated_calf_machine"], reps: 10),
                    routine("FBEOD C", ["pendulum_squat_machine", "machine_chest_press", "seated_cable_row", "seated_hamstring_curl", "reverse_pecdeck_fly", "cable_ab_crunch"], reps: 12)
                ]
            ),
            SuggestedRoutineProgram(
                id: "full_body_three_days",
                title: isGerman ? "Ganzkörper Basis" : "Full-Body Foundation",
                summary: isGerman ? "Ein verständlicher Ganzkörperplan für drei Trainingstage und jedes Erfahrungsniveau." : "A straightforward full-body plan for three training days and any experience level.",
                daysPerWeek: 3,
                style: .general,
                routines: [
                    routine(isGerman ? "Ganzkörper A" : "Full Body A", ["barbell_back_squat", "barbell_bench_press", "dumbbell_row", "lateral_raise", "plank"]),
                    routine(isGerman ? "Ganzkörper B" : "Full Body B", ["conventional_deadlift", "overhead_press", "lat_pulldown", "leg_press", "biceps_curl"])
                ]
            ),
            SuggestedRoutineProgram(
                id: "dumbbell_only",
                title: isGerman ? "Nur Kurzhanteln" : "Dumbbells Only",
                summary: isGerman ? "Ganzkörpertraining für Zuhause mit Kurzhanteln und ohne Maschinen." : "At-home full-body training with dumbbells and no machines.",
                daysPerWeek: 3,
                style: .general,
                routines: [
                    routine(isGerman ? "Kurzhantel A" : "Dumbbell A", ["goblet_squat", "incline_dumbbell_press", "dumbbell_row", "lateral_raise", "plank"]),
                    routine(isGerman ? "Kurzhantel B" : "Dumbbell B", ["dumbbell_rdl", "dumbbell_shoulder_press", "dumbbell_row", "biceps_curl", "reverse_lunge"])
                ]
            ),
            SuggestedRoutineProgram(
                id: "bodyweight_only",
                title: isGerman ? "Ohne Equipment" : "No Equipment",
                summary: isGerman ? "Körpergewichtstraining für Zuhause oder unterwegs – ganz ohne Geräte." : "Bodyweight training for home or travel with no equipment required.",
                daysPerWeek: 3,
                style: .general,
                routines: [
                    routine(isGerman ? "Körpergewicht A" : "Bodyweight A", ["bodyweight_squat", "push_up", "reverse_lunge", "pike_push_up", "plank"], reps: 12),
                    routine(isGerman ? "Körpergewicht B" : "Bodyweight B", ["glute_bridge", "push_up", "bodyweight_squat", "mountain_climber", "plank"], reps: 15)
                ]
            ),
            SuggestedRoutineProgram(
                id: "resistance_bands_only",
                title: isGerman ? "Resistance Bands" : "Resistance Bands",
                summary: isGerman ? "Drei kompakte Ganzkörpereinheiten nur mit Resistance Bands." : "Three compact full-body sessions using resistance bands only.",
                daysPerWeek: 3,
                style: .general,
                routines: [
                    routine(isGerman ? "Band Ganzkörper A" : "Band Full Body A", ["band_squat", "band_chest_press", "band_row", "band_lateral_raise", "plank"], reps: 15),
                    routine(isGerman ? "Band Ganzkörper B" : "Band Full Body B", ["band_rdl", "band_chest_press", "band_row", "band_face_pull", "glute_bridge"], reps: 15)
                ]
            ),
            SuggestedRoutineProgram(
                id: "kettlebell_only",
                title: isGerman ? "Kettlebell Kraft & Kondition" : "Kettlebell Strength & Conditioning",
                summary: isGerman ? "Kraft, Explosivität und Kondition mit einer Kettlebell." : "Strength, power and conditioning with a single kettlebell.",
                daysPerWeek: 3,
                style: .general,
                routines: [
                    routine(isGerman ? "Kettlebell A" : "Kettlebell A", ["kettlebell_goblet", "kettlebell_press", "kettlebell_row", "kettlebell_swing", "plank"], reps: 10),
                    routine(isGerman ? "Kettlebell B" : "Kettlebell B", ["kettlebell_swing", "kettlebell_goblet", "kettlebell_row", "reverse_lunge", "mountain_climber"], reps: 12)
                ]
            ),
            SuggestedRoutineProgram(
                id: "gym_machines_only",
                title: isGerman ? "Maschinen Ganzkörper" : "Machine Full Body",
                summary: isGerman ? "Ein stabiler, leicht zugänglicher Plan mit Maschinen und Kabelzügen." : "A stable, approachable plan using machines and cables.",
                daysPerWeek: 3,
                style: .general,
                routines: [
                    routine(isGerman ? "Maschinen A" : "Machines A", ["hack_squat_machine", "machine_chest_press", "onearm_lat_pulldown", "seated_hamstring_curl", "overhead_cable_triceps"]),
                    routine(isGerman ? "Maschinen B" : "Machines B", ["leg_extension", "supported_chest_row", "machine_shoulder_press", "hip_abduction_machine", "seated_calf_machine"])
                ]
            ),
            SuggestedRoutineProgram(
                id: "strong_women",
                title: isGerman ? "Strong Women: Unterkörper & Core" : "Strong Women: Lower Body & Core",
                summary: isGerman ? "Drei ausgewogene Einheiten mit Fokus auf Gesäß, Beine, Core und Oberkörperkraft." : "Three balanced sessions focused on glutes, legs, core and upper-body strength.",
                daysPerWeek: 3,
                style: .womenFocus,
                routines: [
                    routine(isGerman ? "Glutes & Beine" : "Glutes & Legs", ["hip_thrust", "barbell_back_squat", "romanian_deadlift", "seated_hamstring_curl", "standing_calf_raise"]),
                    routine(isGerman ? "Oberkörper & Core" : "Upper Body & Core", ["dumbbell_row", "incline_dumbbell_press", "dumbbell_shoulder_press", "lat_pulldown", "plank"]),
                    routine(isGerman ? "Unterkörper Volumen" : "Lower Body Volume", ["hip_thrust", "leg_press", "reverse_lunge", "leg_extension", "glute_bridge"], reps: 12)
                ]
            ),
            SuggestedRoutineProgram(
                id: "running_foundation",
                title: isGerman ? "Lauf-Ausdauer Basis" : "Running Endurance Foundation",
                summary: isGerman ? "Lockerer Lauf, Intervalle und langer Lauf für eine ausgewogene Ausdauerwoche." : "Easy running, intervals and a long run for a balanced endurance week.",
                daysPerWeek: 3,
                style: .endurance,
                routines: [
                    routine(isGerman ? "Lockerer Lauf" : "Easy Run", ["outdoor_run", "plank"], sets: 1),
                    routine(isGerman ? "Laufintervalle" : "Run Intervals", ["treadmill_run", "mountain_climber"], sets: 4, rest: 60),
                    routine(isGerman ? "Langer Lauf" : "Long Run", ["outdoor_run"], sets: 1)
                ]
            ),
            SuggestedRoutineProgram(
                id: "hybrid_conditioning",
                title: isGerman ? "Hybrid Ausdauer & Kraft" : "Hybrid Conditioning",
                summary: isGerman ? "Krafttraining kombiniert mit Laufen, Rad und Ruderergometer." : "Strength training combined with running, cycling and rowing.",
                daysPerWeek: 4,
                style: .endurance,
                routines: [
                    routine(isGerman ? "Hybrid Kraft A" : "Hybrid Strength A", ["barbell_back_squat", "barbell_bench_press", "dumbbell_row", "stationary_bike"]),
                    routine(isGerman ? "Hybrid Kraft B" : "Hybrid Strength B", ["romanian_deadlift", "overhead_press", "pull_up", "rowing_ergometer"]),
                    routine(isGerman ? "Ausdauer" : "Endurance", ["outdoor_run", "jump_rope"], sets: 1)
                ]
            )
        ]
    }
}

enum TrainingSyncState: Equatable { case local, syncing, synced(Date), offline, failed }

nonisolated struct TrainingStatistics: Sendable {
    let workoutCount: Int
    let totalDuration: TimeInterval
    let totalVolume: Double
    let currentStreak: Int
    let longestStreak: Int
    let trainedThisWeek: Bool
    let workoutsThisWeek: Int
    let setsThisWeek: Double
    let personalRecordCount: Int
    let averageWorkoutsPerWeek: Double
}

nonisolated struct ExerciseProgressPoint: Identifiable, Sendable {
    let id: UUID
    let date: Date
    let bestWeightKilograms: Double
    let bestRepetitions: Int
    let bestSetVolume: Double
    let estimatedOneRepMaximum: Double
    let distanceMeters: Double
    let durationSeconds: Double
    let paceSecondsPerKilometer: Double?
}

nonisolated struct ExerciseProgressSummary: Sendable {
    let exerciseID: UUID
    let workoutCount: Int
    let completedSetCount: Int
    let bestWeightKilograms: Double
    let bestRepetitions: Int
    let bestSetVolume: Double
    let estimatedOneRepMaximum: Double
    let totalDistanceMeters: Double
    let totalDurationSeconds: Double
    let bestPaceSecondsPerKilometer: Double?
    let points: [ExerciseProgressPoint]
}

nonisolated struct MuscleTrainingVolume: Identifiable, Sendable {
    let muscle: String
    let completedSets: Double
    let volume: Double
    var id: String { muscle }
}

nonisolated struct TrainingServerStreak: Codable, Sendable {
    let currentStreak: Int
    let longestStreak: Int
    let lastValidTrainingDay: String

    enum CodingKeys: String, CodingKey {
        case currentStreak = "current_streak"
        case longestStreak = "longest_streak"
        case lastValidTrainingDay = "last_valid_training_day"
    }
}
