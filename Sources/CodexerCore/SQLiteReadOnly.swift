import Foundation

enum SQLiteReadOnly {
    static func databaseArgument(
        for database: URL,
        fileManager: FileManager = .default
    ) -> String {
        let wal = URL(fileURLWithPath: database.path + "-wal")
        let sharedMemory = URL(fileURLWithPath: database.path + "-shm")
        guard
            !fileManager.fileExists(atPath: wal.path),
            !fileManager.fileExists(atPath: sharedMemory.path)
        else {
            return database.path
        }
        return database.absoluteString + "?immutable=1"
    }
}
