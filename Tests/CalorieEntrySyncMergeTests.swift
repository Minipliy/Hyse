import Foundation

@main
enum CalorieEntrySyncMergeTests {
    static func main() {
        let original = UUID()
        let missing = UUID()
        let newRemote = UUID()
        let local = [original: "old amount", missing: "saved locally"]
        let remote = [original: "server amount", newRemote: "other device"]

        let incomplete = CalorieEntrySyncMerge.reconcile(
            local: local, remote: remote, confirmedRemoteIDs: Set(remote.keys),
            pendingDirtyIDs: [], pendingDeletedIDs: [], didFullFetch: true
        )
        expect(incomplete.entries[original] == "server amount", "confirmed server updates remain visible")
        expect(incomplete.entries[missing] == "saved locally", "an incomplete full fetch does not erase diary entries")
        expect(incomplete.entries[newRemote] == "other device", "new entries from another device are included")
        expect(incomplete.retryIDs == [missing], "missing local entries are queued for upload")

        let deleted = CalorieEntrySyncMerge.reconcile(
            local: local, remote: remote, confirmedRemoteIDs: Set(remote.keys),
            pendingDirtyIDs: [], pendingDeletedIDs: [missing], didFullFetch: true
        )
        expect(deleted.entries[missing] == nil, "an explicit deletion still removes the entry")
        expect(deleted.retryIDs.isEmpty, "deleted entries are never reuploaded")

        let pendingEdit = CalorieEntrySyncMerge.reconcile(
            local: local, remote: remote, confirmedRemoteIDs: Set(remote.keys),
            pendingDirtyIDs: [original], pendingDeletedIDs: [], didFullFetch: false
        )
        expect(pendingEdit.entries[original] == "old amount", "an unsynced local edit wins over a stale response")
        expect(pendingEdit.entries[missing] == "saved locally", "incremental sync keeps existing entries")
        print("Calorie entry sync merge tests passed.")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fatalError(message) }
    }
}
