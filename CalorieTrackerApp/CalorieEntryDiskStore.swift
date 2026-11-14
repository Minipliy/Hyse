import Foundation

/// Stores diary snapshots before a save is reported as complete. The atomic
/// replacement also keeps the previous snapshot intact if a write fails.
struct CalorieEntryDiskStore {
    private let directory: URL

    init(directory: URL? = nil) throws {
        if let directory {
            self.directory = directory
        } else {
            let applicationSupport = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            self.directory = applicationSupport
                .appendingPathComponent("Hyse", isDirectory: true)
                .appendingPathComponent("CalorieEntries", isDirectory: true)
        }
    }

    func write(_ data: Data, forKey key: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let current = fileURL(forKey: key)
        let previous = previousFileURL(forKey: key)
        if FileManager.default.fileExists(atPath: current.path) {
            // Keep the last complete snapshot for recovery if a later version
            // can no longer decode the primary file.
            let staged = previous.appendingPathExtension("staged")
            try? FileManager.default.removeItem(at: staged)
            try FileManager.default.copyItem(at: current, to: staged)
            if FileManager.default.fileExists(atPath: previous.path) {
                _ = try FileManager.default.replaceItemAt(previous, withItemAt: staged)
            } else {
                try FileManager.default.moveItem(at: staged, to: previous)
            }
        }
        try data.write(to: current, options: .atomic)
    }

    func read(forKey key: String) -> Data? {
        try? Data(contentsOf: fileURL(forKey: key))
    }

    func readPrevious(forKey key: String) -> Data? {
        try? Data(contentsOf: previousFileURL(forKey: key))
    }

    private func previousFileURL(forKey key: String) -> URL {
        fileURL(forKey: key).appendingPathExtension("previous")
    }

    private func fileURL(forKey key: String) -> URL {
        let name = Data(key.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return directory.appendingPathComponent("\(name).json", isDirectory: false)
    }
}
