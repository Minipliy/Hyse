import Foundation

nonisolated enum HevyImportError: Error {
    case noSupportedFile
    case invalidCSV
}

nonisolated enum HevyImportService {
    private static let workoutHeaders = Set(["title", "start_time", "end_time", "exercise_title", "set_type"])
    private static let measurementHeaders = Set(["date", "weight_kg", "fat_percent"])

    static func parse(_ files: [HevyImportFile], referenceDate: Date = Date()) throws -> ParsedHevyImport {
        var allWorkouts: [WorkoutLog] = []
        var exerciseByID: [UUID: TrainingExercise] = [:]
        var measurements: [BodyMeasurement] = []
        var ignoredRows = 0
        var supportedFiles = 0

        for file in files {
            guard let text = String(data: file.data, encoding: .utf8) else { throw HevyImportError.invalidCSV }
            let table = try CSVTable(text: text)
            let headers = Set(table.headers)
            if workoutHeaders.isSubset(of: headers) {
                supportedFiles += 1
                let result = parseWorkouts(table)
                allWorkouts.append(contentsOf: result.workouts)
                ignoredRows += result.ignoredRows
                for exercise in result.customExercises { exerciseByID[exercise.id] = exercise }
            } else if measurementHeaders.isSubset(of: headers) {
                supportedFiles += 1
                let result = parseMeasurements(table)
                measurements.append(contentsOf: result.measurements)
                ignoredRows += result.ignoredRows
            }
        }

        guard supportedFiles > 0 else { throw HevyImportError.noSupportedFile }
        let workouts = deduplicated(allWorkouts, by: \.id)
        let customExercises = Array(exerciseByID.values)
        return ParsedHevyImport(
            workouts: workouts,
            routines: routines(from: workouts, customExercises: customExercises, referenceDate: referenceDate),
            customExercises: customExercises,
            measurements: deduplicated(measurements, by: \.id),
            ignoredRows: ignoredRows
        )
    }

    /// Use the exercise that will actually be present in Hyse's catalog.
    /// A Hevy export has stable IDs of its own, while an equivalent custom
    /// exercise may already exist in Hyse under a different ID.
    static func resolvingExercises(_ parsed: ParsedHevyImport, against existing: [TrainingExercise]) -> ParsedHevyImport {
        var catalog = existing
        var resolvedByImportedID: [UUID: TrainingExercise] = [:]
        var newExercises: [TrainingExercise] = []

        for imported in parsed.customExercises.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            let existingExercise = catalog.first(where: { $0.id == imported.id })
                ?? TrainingExercise.matchingCatalogExercise(named: imported.englishName, equipment: imported.equipment, in: catalog)
                ?? TrainingExercise.matchingCatalogExercise(named: imported.germanName, equipment: imported.equipment, in: catalog)
            if let existingExercise {
                resolvedByImportedID[imported.id] = existingExercise
                continue
            }

            if TrainingExercise.catalogDeduplicated(catalog + [imported]).contains(where: { $0.id == imported.id }) {
                catalog.append(imported)
                newExercises.append(imported)
                resolvedByImportedID[imported.id] = imported
            }
        }

        let workouts = parsed.workouts.map { workout -> WorkoutLog in
            var value = workout
            value.exercises = workout.exercises.map { log in
                guard let exercise = resolvedByImportedID[log.exerciseID] else { return log }
                var result = log
                result.exerciseID = exercise.id
                result.exerciseNameSnapshot = exercise.englishName
                result.exerciseGermanNameSnapshot = exercise.germanName
                result.exerciseTypeSnapshot = exercise.type
                result.equipmentSnapshot = exercise.equipment
                result.primaryMusclesSnapshot = exercise.primaryMuscles
                result.secondaryMusclesSnapshot = exercise.secondaryMuscles
                return result
            }
            return value
        }
        let routines = parsed.routines.map { routine -> WorkoutRoutine in
            var value = routine
            value.exercises = routine.exercises.map { item in
                guard let exercise = resolvedByImportedID[item.exercise.id] else { return item }
                var result = item
                result.exercise = exercise
                result.sets = item.sets.map { $0.normalized(for: exercise.type) }
                return result
            }
            return value
        }
        return ParsedHevyImport(
            workouts: workouts,
            routines: routines,
            customExercises: newExercises,
            measurements: parsed.measurements,
            ignoredRows: parsed.ignoredRows
        )
    }

    /// Hevy's workout CSV contains completed sessions, not saved routine records.
    /// Only sessions from the rolling month before import can supply templates.
    /// The latest eligible session for each name supplies the editable values.
    private static func routines(from workouts: [WorkoutLog], customExercises: [TrainingExercise], referenceDate: Date) -> [WorkoutRoutine] {
        let cutoff = Calendar.current.date(byAdding: .month, value: -1, to: referenceDate) ?? referenceDate.addingTimeInterval(-30 * 24 * 60 * 60)
        let catalog = Dictionary(uniqueKeysWithValues: (TrainingExercise.builtIns + customExercises).map { ($0.id, $0) })
        var seenNames = Set<String>()
        return workouts.filter { $0.startedAt >= cutoff && $0.startedAt <= referenceDate }
            .sorted { $0.startedAt > $1.startedAt }
            .compactMap { workout in
            let nameKey = normalized(workout.name)
            guard !nameKey.isEmpty, seenNames.insert(nameKey).inserted, !workout.exercises.isEmpty else { return nil }
            let routineExercises = workout.exercises.compactMap { log -> RoutineExercise? in
                guard let exercise = catalog[log.exerciseID] else { return nil }
                let sets = log.sets.map { source -> TrainingSetLog in
                    var set = source.normalized(for: exercise.type)
                    set.id = stableUUID("hevy-routine-set|\(nameKey)|\(log.exerciseID)|\(source.id)")
                    set.completed = false
                    set.completedAt = nil
                    set.personalRecordFlags = []
                    return set
                }
                return RoutineExercise(
                    id: stableUUID("hevy-routine-exercise|\(nameKey)|\(log.exerciseID)"),
                    exercise: exercise,
                    notes: log.notes,
                    restSeconds: log.restSeconds,
                    supersetGroup: log.supersetGroup,
                    sets: sets.isEmpty ? [TrainingSetLog()] : sets
                )
            }
            guard !routineExercises.isEmpty else { return nil }
            return WorkoutRoutine(
                id: stableUUID("hevy-routine|\(nameKey)"),
                name: workout.name,
                exercises: routineExercises,
                updatedAt: workout.completedAt ?? workout.startedAt
            )
        }
    }

    private static func parseWorkouts(_ table: CSVTable) -> (workouts: [WorkoutLog], customExercises: [TrainingExercise], ignoredRows: Int) {
        struct ExerciseBuilder {
            var title: String
            var notes: String
            var supersetGroup: String?
            var type: TrainingExerciseType
            var equipment: TrainingEquipment
            var sets: [TrainingSetLog]
        }
        struct WorkoutBuilder {
            var id: UUID
            var title: String
            var start: Date
            var end: Date
            var notes: String
            var exercises: [ExerciseBuilder]
            var exerciseIndexes: [String: Int]
        }

        var builders: [WorkoutBuilder] = []
        var workoutIndexes: [String: Int] = [:]
        var ignoredRows = 0

        for (rowIndex, row) in table.rows.enumerated() {
            let title = value("title", row).trimmed
            let exerciseTitle = value("exercise_title", row).trimmed
            guard !title.isEmpty, !exerciseTitle.isEmpty,
                  let start = hevyDate(value("start_time", row)) else {
                ignoredRows += 1
                continue
            }
            let end = hevyDate(value("end_time", row)) ?? start
            let workoutKey = "\(normalized(title))|\(start.timeIntervalSince1970)"
            let workoutIndex: Int
            if let existing = workoutIndexes[workoutKey] {
                workoutIndex = existing
            } else {
                workoutIndex = builders.count
                workoutIndexes[workoutKey] = workoutIndex
                builders.append(WorkoutBuilder(
                    id: stableUUID("hevy-workout|\(workoutKey)"),
                    title: title,
                    start: start,
                    end: max(end, start),
                    notes: value("description", row).trimmed,
                    exercises: [],
                    exerciseIndexes: [:]
                ))
            }

            builders[workoutIndex].end = max(builders[workoutIndex].end, end)
            let exerciseKey = normalized(exerciseTitle)
            let exerciseIndex: Int
            if let existing = builders[workoutIndex].exerciseIndexes[exerciseKey] {
                exerciseIndex = existing
            } else {
                exerciseIndex = builders[workoutIndex].exercises.count
                builders[workoutIndex].exerciseIndexes[exerciseKey] = exerciseIndex
                builders[workoutIndex].exercises.append(ExerciseBuilder(
                    title: exerciseTitle,
                    notes: value("exercise_notes", row).trimmed,
                    supersetGroup: nonempty(value("superset_id", row)),
                    type: inferredType(row),
                    equipment: inferredEquipment(exerciseTitle),
                    sets: []
                ))
            }

            let completedAt = max(end, start)
            var set = TrainingSetLog(
                id: stableUUID("hevy-set|\(workoutKey)|\(exerciseKey)|\(rowIndex)"),
                type: setType(value("set_type", row), isSuperset: nonempty(value("superset_id", row)) != nil),
                weightKilograms: positiveDouble(value("weight_kg", row)),
                reps: max(0, int(value("reps", row))),
                durationSeconds: positiveDouble(value("duration_seconds", row)),
                distanceMeters: positiveDouble(value("distance_km", row)) * 1_000,
                rpe: optionalDouble(value("rpe", row)),
                completed: true,
                completedAt: completedAt,
                updatedAt: completedAt
            )
            if set.rpe.map({ !(0...10).contains($0) }) == true { set.rpe = nil }
            builders[workoutIndex].exercises[exerciseIndex].sets.append(set)
        }

        var customByID: [UUID: TrainingExercise] = [:]
        let workouts = builders.map { builder in
            let exercises = builder.exercises.map { item -> WorkoutExerciseLog in
                let matched = TrainingExercise.matchingBuiltIn(named: item.title)
                let exercise: TrainingExercise
                if let matched {
                    exercise = matched
                } else {
                    let id = stableUUID("hevy-exercise|\(normalized(item.title))")
                    exercise = TrainingExercise(
                        id: id,
                        nameKey: "hevy_import",
                        englishName: item.title,
                        germanName: item.title,
                        descriptionKey: "",
                        techniqueKey: "",
                        type: item.type,
                        equipment: item.equipment,
                        primaryMuscles: [],
                        secondaryMuscles: [],
                        isCustom: true,
                        isFavorite: false,
                        updatedAt: builder.end
                    ).normalizedImportedCatalogEntry()
                    customByID[id] = exercise
                }
                return WorkoutExerciseLog(
                    id: stableUUID("hevy-placement|\(builder.id.uuidString)|\(normalized(item.title))"),
                    exerciseID: exercise.id,
                    exerciseNameSnapshot: exercise.englishName,
                    exerciseGermanNameSnapshot: exercise.germanName,
                    exerciseTypeSnapshot: item.type,
                    equipmentSnapshot: item.equipment,
                    primaryMusclesSnapshot: exercise.primaryMuscles,
                    secondaryMusclesSnapshot: exercise.secondaryMuscles,
                    notes: item.notes,
                    restSeconds: 90,
                    supersetGroup: item.supersetGroup,
                    sets: item.sets
                )
            }
            return WorkoutLog(
                id: builder.id,
                name: builder.title,
                status: .completed,
                startedAt: builder.start,
                completedAt: builder.end,
                timezone: TimeZone.autoupdatingCurrent.identifier,
                notes: builder.notes,
                exercises: exercises,
                updatedAt: builder.end
            )
        }
        return (workouts, Array(customByID.values), ignoredRows)
    }

    private static func parseMeasurements(_ table: CSVTable) -> (measurements: [BodyMeasurement], ignoredRows: Int) {
        let dimensionKeys = table.headers.filter { $0.hasSuffix("_cm") }
        var ignoredRows = 0
        var result: [BodyMeasurement] = []
        for row in table.rows {
            guard let date = hevyDate(value("date", row)) else { ignoredRows += 1; continue }
            let weight = optionalDouble(value("weight_kg", row))
            let fat = optionalDouble(value("fat_percent", row))
            var dimensions: [String: Double] = [:]
            for key in dimensionKeys {
                if let measurement = optionalDouble(value(key, row)) { dimensions[key] = measurement }
            }
            guard weight != nil || fat != nil || !dimensions.isEmpty else { ignoredRows += 1; continue }
            result.append(BodyMeasurement(
                id: stableUUID("hevy-measurement|\(date.timeIntervalSince1970)"),
                date: date,
                weightKilograms: weight,
                bodyFatPercentage: fat,
                centimeters: dimensions,
                source: "hevy",
                updatedAt: date
            ))
        }
        return (result, ignoredRows)
    }

    private static func inferredType(_ row: [String: String]) -> TrainingExerciseType {
        if positiveDouble(value("distance_km", row)) > 0 { return .distanceDuration }
        if positiveDouble(value("duration_seconds", row)) > 0 && int(value("reps", row)) == 0 { return .duration }
        if positiveDouble(value("weight_kg", row)) > 0 { return .weightReps }
        return .repsOnly
    }

    private static func inferredEquipment(_ title: String) -> TrainingEquipment {
        let text = normalized(title)
        if text.contains("langhantel") || text.contains("barbell") { return .barbell }
        if text.contains("kurzhantel") || text.contains("dumbbell") { return .dumbbell }
        if text.contains("maschine") || text.contains("machine") || text.contains("multipresse") { return .machine }
        if text.contains("kabel") || text.contains("cable") || text.contains("seil") { return .cable }
        if text.contains("band") { return .bands }
        if text.contains("lauf") || text.contains("treadmill") || text.contains("radfahren") || text.contains("cycling") { return .cardio }
        if text.contains("körpergewicht") || text.contains("bodyweight") || text.contains("klimmzug") || text.contains("liegestütz") { return .bodyweight }
        return .other
    }

    private static func setType(_ raw: String, isSuperset: Bool) -> TrainingSetType {
        if isSuperset { return .superset }
        switch normalized(raw).replacingOccurrences(of: " ", with: "_") {
        case "warmup", "warm_up": return .warmup
        case "dropset", "drop_set": return .dropSet
        case "failure": return .failure
        default: return .normal
        }
    }

    private static func hevyDate(_ raw: String) -> Date? {
        let replacements = [
            ("Januar", "January"), ("Februar", "February"), ("März", "Mar"),
            ("Mai", "May"), ("Juni", "Jun"), ("Juli", "Jul"),
            ("September", "September"), ("Oktober", "October"), ("November", "November"), ("Dezember", "December"),
            ("Sept.", "Sep"), ("Sept", "Sep"), ("Okt.", "Oct"), ("Okt", "Oct"),
            ("Nov.", "Nov"), ("Dez.", "Dec"), ("Dez", "Dec")
        ]
        var text = raw.trimmed
        for (source, target) in replacements { text = text.replacingOccurrences(of: source, with: target, options: .caseInsensitive) }
        for format in ["d MMM yyyy, HH:mm", "d MMMM yyyy, HH:mm", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ssZ"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.timeZone = .autoupdatingCurrent
            formatter.dateFormat = format
            if let date = formatter.date(from: text) { return date }
        }
        return nil
    }

    private static func value(_ header: String, _ row: [String: String]) -> String { row[header] ?? "" }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }
    private static func nonempty(_ value: String) -> String? { value.trimmed.isEmpty ? nil : value.trimmed }
    private static func optionalDouble(_ value: String) -> Double? { Double(value.trimmed.replacingOccurrences(of: ",", with: ".")) }
    private static func positiveDouble(_ value: String) -> Double { max(0, optionalDouble(value) ?? 0) }
    private static func int(_ value: String) -> Int { Int(Double(value.trimmed) ?? 0) }

    private static func stableUUID(_ value: String) -> UUID {
        func hash(seed: UInt64) -> UInt64 {
            value.utf8.reduce(seed) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 }
        }
        let first = hash(seed: 14_695_981_039_346_656_037)
        let second = hash(seed: 10_995_116_282_111)
        var bytes = withUnsafeBytes(of: first.bigEndian, Array.init) + withUnsafeBytes(of: second.bigEndian, Array.init)
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7], bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    private static func deduplicated<T>(_ values: [T], by keyPath: KeyPath<T, UUID>) -> [T] {
        var seen = Set<UUID>()
        return values.filter { seen.insert($0[keyPath: keyPath]).inserted }
    }
}

private nonisolated struct CSVTable {
    let headers: [String]
    let rows: [[String: String]]

    init(text: String) throws {
        let parsed = Self.parseRows(text)
        guard let first = parsed.first, !first.isEmpty else { throw HevyImportError.invalidCSV }
        let normalizedHeaders = first.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        headers = normalizedHeaders
        rows = Array(parsed.dropFirst())
            .filter { $0.contains { !$0.trimmed.isEmpty } }
            .map { values in
                var row: [String: String] = [:]
                for (index, header) in normalizedHeaders.enumerated() {
                    row[header] = values.indices.contains(index) ? values[index] : ""
                }
                return row
            }
    }

    private static func parseRows(_ text: String) -> [[String]] {
        var rows: [[String]] = [], row: [String] = [], field = ""
        var quoted = false
        let characters = Array(text)
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character == "\"" {
                if quoted, index + 1 < characters.count, characters[index + 1] == "\"" { field.append("\""); index += 1 }
                else { quoted.toggle() }
            } else if character == ",", !quoted {
                row.append(field); field = ""
            } else if (character == "\n" || character == "\r" || character == "\r\n"), !quoted {
                if character == "\r", index + 1 < characters.count, characters[index + 1] == "\n" { index += 1 }
                row.append(field); field = ""
                rows.append(row); row = []
            } else { field.append(character) }
            index += 1
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }
}

private extension String {
    nonisolated var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
