//
//  SqliteStore.swift
//  SqliteStore
//
//  Created by Aikyuichi on 16/10/25.
//  Copyright (c) 2022 aikyuichi <aikyu.sama@gmail.com>
//  Use of this source code is governed by a MIT license that can be found in the LICENSE file.
//

import Foundation

/// Registry helpers for opening and managing named SQLite databases.
extension Database {
    /// Registers a database at a filesystem path.
    ///
    /// - Parameters:
    ///   - path: Filesystem path to the database file.
    ///   - key: Key used to retrieve and open the registered database.
    ///   - attachements: Mapping of SQLite schema names to keys of other registered databases to attach when opening this database.
    ///   - readonly: Whether the database should be opened read-only by default.
    ///   - defaultDb: Whether to make this the default database used by APIs that do not specify a key.
    static public func register(path: String, forKey key: String, attachements: [String: String] = [:], readonly: Bool = false, default defaultDb: Bool = false) {
        DbStore.shared.add(
            asset: DbAsset(
                path: path,
                attachements: attachements,
                readonly: readonly
            ),
            forKey: key,
            default: defaultDb
        )
    }
    
    #if os(iOS)
    /// Registers a database resource from the app's main bundle.
    ///
    /// By default, the database is registered at its bundle path. If `copy` is `true`,
    /// the resource is copied to the app's documents directory only if a file with that
    /// name does not already exist there, and the copied file is registered instead.
    ///
    /// - Parameters:
    ///   - name: Name of the database resource, including its file extension.
    ///   - key: Key used to retrieve and open the registered database.
    ///   - attachements: Mapping of SQLite schema names to keys of other registered databases to attach when opening this database.
    ///   - copy: Whether to register a copy in the documents directory instead of the bundle resource.
    ///   - readonly: Whether the database should be opened read-only by default.
    ///   - defaultDb: Whether to make this the default database used by APIs that do not specify a key.
    static public func register(fromMainBundleWithName name: String, forKey key: String, attachements: [String: String] = [:], copyToDocumentDirectory copy: Bool = false, readonly: Bool = false, default defaultDb: Bool = false) {
        let url = NSURL(fileURLWithPath: name)
        let dbPath = Bundle.main.path(forResource: url.deletingPathExtension?.lastPathComponent, ofType: url.pathExtension)!
        if copy {
            if let documentPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first {
                let dbPathTo = (documentPath as NSString).appendingPathComponent(name)
                if !FileManager.default.fileExists(atPath: dbPathTo) {
                    try! FileManager.default.copyItem(atPath: dbPath, toPath: dbPathTo)
                }
                self.register(path: dbPathTo, forKey: key, attachements: attachements, readonly: readonly, default: defaultDb)
            }
        } else {
            self.register(path: dbPath, forKey: key, attachements: attachements, readonly: readonly, default: defaultDb)
        }
    }
    #endif
    
    #if os(iOS)
    /// Registers a database at a path in the app's documents directory.
    ///
    /// - Parameters:
    ///   - name: Database filename, relative to the documents directory.
    ///   - key: Key used to retrieve and open the registered database.
    ///   - attachements: Mapping of SQLite schema names to keys of other registered databases to attach when opening this database.
    ///   - readonly: Whether the database should be opened read-only by default.
    ///   - defaultDb: Whether to make this the default database used by APIs that do not specify a key.
    static public func register(fromDocumentDirectoryWithName name: String, forKey key: String, attachements: [String: String] = [:], readonly: Bool = false, default defaultDb: Bool = false) {
        if let documentPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first {
            let dbPath = (documentPath as NSString).appendingPathComponent(name)
            self.register(path: dbPath, forKey: key, attachements: attachements, readonly: readonly, default: defaultDb)
        }
    }
    #endif
    
    /// Removes a registered database and any cached open connection for the provided key.
    static public func unregister(forkey key: String) {
        DbStore.shared.remove(dbKey: key)
    }
    
    /// Returns the default registered database.
    static public func get() throws -> Database {
        let key = DbStore.shared.getDefaultDbKey()
        return try get(forKey: key)
    }
    
    /// Returns the registered database for the provided key.
    static public func get(forKey key: String) throws -> Database {
        return try DbStore.shared.getDatabase(forKey: key)
    }
    
    /// Opens the default database, runs the closure, and closes the connection automatically.
    static public func open(readonly: Bool = false, execute code: (_ db: Database) throws -> Void) throws {
        let key = DbStore.shared.getDefaultDbKey()
        try Database.open(forKey: key, readonly: readonly, execute: code)
    }
    
    /// Opens the database associated with a key, runs the closure, and closes the handle afterwards.
    static public func open(forKey key: String, readonly: Bool = false, execute code: (_ db: Database) throws -> Void) throws {
        let dbAsset = try DbStore.shared.getAsset(forKey: key)
        let db = try Database.open(dbAsset.path, readonly: readonly)
        defer { db.close() }
        for (schema, dbKey) in dbAsset.attachements {
            if let attachementAsset = try? DbStore.shared.getAsset(forKey: dbKey) {
                try db.attach(databaseAtPath: attachementAsset.path, withSchema: schema)
            }
        }
        try code(db)
    }
    
    /// Applies pending database updates described by an updates JSON file.
    ///
    /// When `databaseFile` or `withKey` identifies a database, only that database is updated.
    /// When `databaseFile` and `withKey` are supplied, the updates of that key are applied to the database.
    /// Otherwise, updates are applied to registered databases whose keys appear in the update
    /// definitions. If `updatesSource` is `nil`, the method looks for `updates.json` in the main
    /// bundle. Errors are not thrown: execution errors are passed to `after`, while errors
    /// encountered while loading definitions or resolving database keys are only printed in
    /// debug builds.
    ///
    /// - Parameters:
    ///   - databaseFile: Path to the database file to update. When provided without `withKey`,
    ///     the key is derived from the filename without its extension.
    ///   - key: Identifies a set of updates. When provided without `databaseFile`, the
    ///     database path is resolved from the store using the key as a registered database.
    ///   - updatesSource: Path to the JSON file containing update definitions, or `nil` to use
    ///     `updates.json` from the main bundle.
    ///   - before: Callback invoked before each applicable update is executed.
    ///   - after: Callback invoked after an update attempt; `error` is `nil` on success.
    static public func update(_ databaseFile: String? = nil, withKey key: String? = nil, using updatesSource: String? = nil, before: ((_ update: [String: Any?]) -> Void)? = nil, after: ((_ update: [String: Any?], _ error: Error?) -> Void)? = nil) {
        do {
            var _databaseFile = databaseFile
            if let key, _databaseFile == nil {
                _databaseFile = try DbStore.shared.getAsset(forKey: key).path
            }
            var _key = key
            if let databaseFile, _key == nil {
                _key = NSString(string: NSString(string: databaseFile).deletingPathExtension).lastPathComponent
            }
            if let _databaseFile, let _key {
                let updates = try getUpdates(fromSource: updatesSource, forKey: _key)
                let updater = DbUpdater(databaseFile: _databaseFile, updates: updates.first!.value, beforeUpdate: before, afterUpdate: after)
                updater.run()
            } else {
                let updates = try getUpdates(fromSource: updatesSource, forKey: key)
                for (key, updateEntries) in updates {
                    if let dbAsset = try? DbStore.shared.getAsset(forKey: key) {
                        let updater = DbUpdater(databaseFile: dbAsset.path, updates: updateEntries, beforeUpdate: before, afterUpdate: after)
                        updater.run()
                    }
                }
            }
        } catch {
            #if DEBUG
            print(error)
            #endif
        }
    }
    
    /// Closes one database or all cached databases when a key is not supplied.
    static public func close(forKey key: String? = nil) {
        DbStore.shared.close(dbKey: key)
    }
    
    /// Registers a callback to receive SQLite errors raised by the shared store.
    static public func onError(callback: @escaping (SQLiteError) -> Void) {
        DbStore.shared.setErrorHandler(callback)
    }
    
    /// Loads update definitions from the given source or the bundled default file.
    ///
    /// - Parameters:
    ///   - source: Path to the JSON file, or `nil` to use the bundled `updates.json`.
    ///   - key: Optional identifier used to select one set of updates.
    /// - Returns: Update entries grouped by key.
    /// - Throws: An error if the selected file cannot be read or parsed, or if an update
    ///   definition is invalid.
    static private func getUpdates(fromSource source: String?, forKey key: String?) throws -> [String: [UpdateEntry]] {
        if let source = source ?? Bundle.main.path(forResource: "updates", ofType: "json") {
            return try getUpdates(fromFile: source, forKey: key)
        }
        return [:]
    }
    
    /// Parses update definitions from a JSON file.
    ///
    /// - Parameters:
    ///   - file: Path to the JSON file, or `nil` to use the bundled `updates.json`.
    ///   - key: Optional identifier used to select one set of updates.
    /// - Returns: Update entries grouped by key.
    /// - Throws: An `UpdateError` if the file is missing or the requested key is absent, or an
    ///   error if the file cannot be read or parsed.
    static private func getUpdates(fromFile file: String?, forKey key: String?) throws -> [String: [UpdateEntry]] {
        guard let file = file ?? Bundle.main.path(forResource: "updates", ofType: "json") else {
            throw UpdateError.invalidFormat("updates.json not found in bundle")
        }
        var updates: [String: [UpdateEntry]] = [:]
        if let data = try String(contentsOfFile: file).data(using: .utf8),
           let json = try JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] {
            if let key {
                if let value = json[key] {
                    updates[key] = try getUpdateEntries(value, forKey: key)
                } else {
                    throw UpdateError.invalidFormat("key: \"\(key)\" not found in updates.json")
                }
            } else {
                for (key, value) in json {
                    updates[key] = try getUpdateEntries(value, forKey: key)
                }
            }
        }
        return updates
    }
    
    /// Parses and orders the versioned update entries for one database.
    ///
    /// - Parameters:
    ///   - json: JSON object containing a `versions` dictionary.
    ///   - key: Identifier associated with these update entries.
    /// - Returns: Update entries sorted by ascending version.
    /// - Throws: An `UpdateError` if the `versions` dictionary is missing or an entry does not
    ///   contain valid update commands.
    static private func getUpdateEntries(_ json: [String: Any], forKey key: String) throws -> [UpdateEntry] {
        guard let json = json["versions"] as? [String: [String: Any]] else {
            throw UpdateError.invalidFormat("key: \"versions\" not found in updates.json")
        }
        var entries: [UpdateEntry] = []
        let versionIds = json.keys.sorted { Int($0)! < Int($1)! }
        for versionId in versionIds {
            let entry = try UpdateEntry(key: key, version: Int(versionId)!, json: json[versionId]!)
            entries.append(entry)
        }
        return entries
    }
}
