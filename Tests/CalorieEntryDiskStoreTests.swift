import Foundation

@main
enum CalorieEntryDiskStoreTests {
    static func main() throws {
        if CommandLine.arguments.count == 3 {
            let mode = CommandLine.arguments[1]
            let directory = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
            let store = try CalorieEntryDiskStore(directory: directory)
            switch mode {
            case "write":
                try store.write(Data("saved food".utf8), forKey: "calorie_entries_account/test")
                try store.write(Data("guest food".utf8), forKey: "calorie_entries_guest")
            case "read":
                guard store.read(forKey: "calorie_entries_account/test") == Data("saved food".utf8),
                      store.read(forKey: "calorie_entries_guest") == Data("guest food".utf8) else {
                    fatalError("The account and guest entries did not survive a process restart")
                }
            case "edit":
                try store.write(Data("edited amount".utf8), forKey: "calorie_entries_account/test")
            case "read-edited":
                guard store.read(forKey: "calorie_entries_account/test") == Data("edited amount".utf8),
                      store.readPrevious(forKey: "calorie_entries_account/test") == Data("saved food".utf8),
                      store.read(forKey: "calorie_entries_guest") == Data("guest food".utf8) else {
                    fatalError("An edited amount did not survive a process restart")
                }
            case "edit-again":
                try store.write(Data("newer amount".utf8), forKey: "calorie_entries_account/test")
            case "read-latest":
                guard store.read(forKey: "calorie_entries_account/test") == Data("newer amount".utf8),
                      store.readPrevious(forKey: "calorie_entries_account/test") == Data("edited amount".utf8) else {
                    fatalError("The previous diary snapshot was not retained")
                }
            default:
                fatalError("Unknown test mode")
            }
            return
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("hyse-entry-persistence-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for mode in ["write", "read", "edit", "read-edited", "edit-again", "read-latest"] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
            process.arguments = [mode, directory.path]
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                fatalError("Persistence subprocess failed: \(mode)")
            }
        }
        print("Diary snapshots and their previous versions survive process restarts.")
    }
}
