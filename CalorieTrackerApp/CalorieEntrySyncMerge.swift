import Foundation

/// Reconciles a server snapshot without treating an absent remote record as
/// proof that the local diary entry should be deleted. Explicit local deletion
/// markers remain authoritative.
enum CalorieEntrySyncMerge {
    static func reconcile<Value>(
        local: [UUID: Value],
        remote: [UUID: Value],
        confirmedRemoteIDs: Set<UUID>,
        pendingDirtyIDs: Set<UUID>,
        pendingDeletedIDs: Set<UUID>,
        didFullFetch: Bool
    ) -> (entries: [UUID: Value], retryIDs: Set<UUID>) {
        var merged = didFullFetch ? [UUID: Value]() : local
        for (id, value) in remote { merged[id] = value }
        for id in confirmedRemoteIDs where merged[id] == nil {
            if let value = local[id] { merged[id] = value }
        }
        for id in pendingDirtyIDs where !pendingDeletedIDs.contains(id) {
            if let value = local[id] { merged[id] = value }
        }
        let retryIDs = didFullFetch
            ? Set(local.keys).subtracting(confirmedRemoteIDs).subtracting(pendingDeletedIDs)
            : []
        for id in retryIDs {
            if let value = local[id] { merged[id] = value }
        }
        for id in pendingDeletedIDs { merged.removeValue(forKey: id) }
        return (merged, retryIDs)
    }
}
