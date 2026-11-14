import Foundation

nonisolated struct TrainingPersonalRecordBest: Sendable {
    private var hasBaseline = false
    private var weight = 0.0
    private var repetitions = 0
    private var volume = 0.0
    private var estimatedOneRepMaximum = 0.0

    mutating func include(_ set: TrainingSetLog) {
        guard set.completed, set.hasRecordablePerformance else { return }
        if hasBaseline {
            weight = max(weight, set.weightKilograms)
            repetitions = max(repetitions, set.reps)
            volume = max(volume, set.volume)
            estimatedOneRepMaximum = max(estimatedOneRepMaximum, set.estimatedOneRepMaximum)
        } else {
            hasBaseline = true
            weight = set.weightKilograms
            repetitions = set.reps
            volume = set.volume
            estimatedOneRepMaximum = set.estimatedOneRepMaximum
        }
    }

    func flags(for candidate: TrainingSetLog) -> [String] {
        guard hasBaseline, candidate.completed, candidate.hasRecordablePerformance else { return [] }
        var flags: [String] = []
        if candidate.weightKilograms > weight { flags.append("weight") }
        if candidate.reps > repetitions { flags.append("reps") }
        if candidate.volume > volume { flags.append("set_volume") }
        if candidate.estimatedOneRepMaximum > estimatedOneRepMaximum { flags.append("estimated_1rm") }
        return flags
    }
}

nonisolated enum TrainingPersonalRecords {
    static func flags(for candidate: TrainingSetLog, comparedWith previousSets: [TrainingSetLog]) -> [String] {
        var best = TrainingPersonalRecordBest()
        for set in previousSets { best.include(set) }
        return best.flags(for: candidate)
    }
}
