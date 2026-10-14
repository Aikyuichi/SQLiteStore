//
//  File.swift
//  SQLiteStore
//
//  Created by Luis Mosquera on 15/7/26.
//

import Foundation

/// Applies a sequence of versioned database updates to a SQLite database.
struct DbUpdater {
    /// The path to the database file that receives the updates.
    private let databaseFile: String
    /// The updates to consider, in the order they are applied.
    private let updates: [UpdateEntry]
    /// An optional callback invoked before an update is executed.
    private let beforeUpdate: ((_ update: [String: Any?]) -> Void)?
    /// An optional callback invoked after an update succeeds or fails.
    private let afterUpdate: ((_ update: [String: Any?], _ error: Error?) -> Void)?
    
    /// Creates an updater for a database and its pending update definitions.
    /// - Parameters:
    ///   - databaseFile: Path to the database file to update.
    ///   - updates: Update entries to process in order.
    ///   - beforeUpdate: Callback invoked before the SQL commands for an applicable update run.
    ///   - afterUpdate: Callback invoked when processing an update finishes; its error is `nil` on success.
    init(databaseFile: String, updates: [UpdateEntry], beforeUpdate: ((_: [String : Any?]) -> Void)?, afterUpdate: ((_: [String : Any?], _: Error?) -> Void)?) {
        self.databaseFile = databaseFile
        self.updates = updates
        self.beforeUpdate = beforeUpdate
        self.afterUpdate = afterUpdate
    }
    
    /// Applies updates whose version is newer than the database's current user version.
    ///
    /// Updates are processed in order. Processing stops at the first failed update unless that
    /// update is configured to be skipped. An empty update list has no effect.
    func run() {
        if updates.isEmpty {
            return
        }
        for update in updates {
            let result = self.executeUpdate(update)
            if !result {
                if update.skipOnError {
                    #if DEBUG
                    print("update failed but skipped: \(update)")
                    #endif
                } else {
                    #if DEBUG
                    print("update failed: \(update)")
                    #endif
                    break
                }
            }
        }
    }
    
    /// Executes one update when its version is newer than the database's current version.
    ///
    /// Attached databases are resolved from the store, and the update's SQL commands and version
    /// change are applied in a transaction. Optional vacuuming and optimization run after commit.
    /// If execution fails, the error is passed to `afterUpdate`; a skippable failure also records
    /// the update's version and attempts to vacuum the database.
    /// - Parameter update: The update definition to execute.
    /// - Returns: `true` if the update was already current or completed successfully; otherwise `false`.
    private func executeUpdate(_ update: UpdateEntry) -> Bool {
        var updateRaw = update.raw
        updateRaw["dbFile"] = self.databaseFile
        do {
            let db = try Database.open(databaseFile)
            defer { db.close() }
            for attach in update.attachments {
                let attachmentAsset = try DbStore.shared.getAsset(forKey: attach)
                try db.attach(databaseAtPath: attachmentAsset.path, withSchema: attach)
            }
            do {
                if db.getUserVersion() < update.version {
                    self.beforeUpdate?(updateRaw)
                    try db.transaction {
                        for command in update.commands {
                            try db.executeQuery(command)
                        }
                        db.setUserVersion(update.version)
                    }
                    if update.vacuum {
                        try db.executeQuery("VACUUM")
                    }
                    if update.optimize {
                        db.optimize()
                    }
                    self.afterUpdate?(updateRaw, nil)
                }
            } catch {
                if update.skipOnError {
                    db.setUserVersion(update.version)
                    if update.vacuum {
                        try? db.executeQuery("VACUUM")
                    }
                }
                self.afterUpdate?(updateRaw, error)
                return false
            }
        } catch {
            self.afterUpdate?(updateRaw, error)
            return false
        }
        return true
    }
}
    
/// Errors encountered while parsing an update definition.
enum UpdateError: Error {
    /// The update definition does not have the required format.
    case invalidFormat(String)
}

/// A parsed database update and the options that control its execution.
internal struct UpdateEntry {
    /// The original update fields, augmented with its key and version.
    fileprivate let raw: [String: Any]
    /// The update's identifier.
    let key: String
    /// The database user version to record after applying the update.
    let version: Int
    /// SQL commands executed as part of the update transaction.
    let commands: [String]
    /// Store keys for database files to attach before executing the commands.
    let attachments: [String]
    /// Whether to vacuum the database after the update.
    let vacuum: Bool
    /// Whether to optimize the database after the update.
    let optimize: Bool
    /// Whether a failed update should be marked as applied and skipped.
    let skipOnError: Bool
    
    /// Creates an update entry from its identifier, version, and JSON fields.
    ///
    /// The `commands` field is required. `attachments`, `vacuum`, `optimize`, and `skipOnError`
    /// are optional and default to an empty list or `false`.
    /// - Parameters:
    ///   - key: Identifier associated with the update.
    ///   - version: Version number associated with the update.
    ///   - json: Update fields, including the required `commands` array.
    /// - Throws: `UpdateError.invalidFormat` if `json` does not contain a string array named `commands`.
    init(key: String, version: Int, json: [String: Any]) throws {
        guard let commands = json["commands"] as? [String] else {
            throw UpdateError.invalidFormat("missing commands")
        }
        self.version = version
        self.key = key
        self.commands = commands
        self.attachments = json["attachments"] as? [String] ?? []
        self.vacuum = json["vacuum"] as? Bool ?? false
        self.optimize = json["optimize"] as? Bool ?? false
        self.skipOnError = json["skipOnError"] as? Bool ?? false
        var _raw = json
        _raw["key"] = key
        _raw["version"] = version
        self.raw = _raw
    }
}
