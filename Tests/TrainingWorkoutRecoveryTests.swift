import Foundation

@MainActor
final class LanguageStore {
    var isGerman = false
    func text(_ key: String, _ arguments: CVarArg...) -> String { key }
}

@main
enum TrainingWorkoutRecoveryTests {
    static func main() {
        let id = UUID()
        let old = Date(timeIntervalSince1970: 100)
        let finished = Date(timeIntervalSince1970: 200)
        var active = WorkoutLog(id: id, name: "Training")
        active.updatedAt = old
        var completed = active
        completed.status = .completed
        completed.completedAt = finished
        completed.updatedAt = finished

        let recovered = TrainingWorkoutRecovery.restoredWorkouts(
            from: [active], journal: active, completedCheckpoint: completed
        )
        expect(recovered.count == 1 && recovered[0].status == .completed,
               "a finished workout must not reappear as active after relaunch")

        let recoveredWithoutSnapshot = TrainingWorkoutRecovery.restoredWorkouts(
            from: [], journal: active, completedCheckpoint: completed
        )
        expect(recoveredWithoutSnapshot.count == 1 && recoveredWithoutSnapshot[0].status == .completed,
               "the checkpoint must recover a missing full-state write")

        let recoveredWithReceipt = TrainingWorkoutRecovery.restoredWorkouts(
            from: [active], journal: active, completedCheckpoint: nil,
            completionReceipts: [id: finished]
        )
        expect(recoveredWithReceipt.count == 1 && recoveredWithReceipt[0].status == .completed,
               "a durable completion receipt must prevent an older active snapshot from reappearing")
        expect(recoveredWithReceipt[0].completedAt == finished,
               "receipt recovery must retain the original finish time")

        var secondActive = WorkoutLog(name: "Second training")
        secondActive.updatedAt = old
        var secondCompleted = secondActive
        secondCompleted.status = .completed
        secondCompleted.completedAt = finished
        secondCompleted.updatedAt = finished
        let recoveredTwoWorkouts = TrainingWorkoutRecovery.restoredWorkouts(
            from: [active, secondActive], journal: secondActive, completedCheckpoint: secondCompleted,
            completionReceipts: [id: finished, secondActive.id: finished]
        )
        expect(recoveredTwoWorkouts.count == 2 && recoveredTwoWorkouts.allSatisfy { $0.status == .completed },
               "finishing another workout must not allow the earlier one to reappear as active")

        var staleRemote = active
        staleRemote.updatedAt = Date(timeIntervalSince1970: 300)
        let protectedRemote = TrainingWorkoutRecovery.applyingCompletionReceipt(to: staleRemote, completedAt: finished)
        expect(protectedRemote.status == .completed,
               "a newer remote active snapshot must not reactivate a finished workout")
        expect(TrainingWorkoutRecovery.shouldKeepCurrent(completed, over: protectedRemote, incomingWasActive: true),
               "a receipt must preserve the completed local sets over a newer remote active snapshot")

        expect(TrainingWorkoutRecovery.shouldKeepCurrent(completed, over: staleRemote),
               "a stale server response must not reactivate a finished workout")

        var edited = completed
        edited.notes = "Edited after finishing"
        edited.updatedAt = Date(timeIntervalSince1970: 400)
        let keptEdit = TrainingWorkoutRecovery.restoredWorkouts(
            from: [edited], journal: nil, completedCheckpoint: completed
        )
        expect(keptEdit[0].notes == edited.notes, "an older checkpoint must not undo later edits")

        print("Workout completion recovery tests passed.")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fatalError(message) }
    }
}
