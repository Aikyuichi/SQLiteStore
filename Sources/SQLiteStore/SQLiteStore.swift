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
    /// Registers a database at a filesystem path and optionally makes it the default database for the process.
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
    /// Loads a database bundle resource, optionally copying it to the documents directory before registration.
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
    /// Registers a database stored in the app's document directory under a given key.
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
    
    /// Applies the JSON migration plan found at the given path or the default `updates.json` bundle resource.
    static public func update(path: String? = nil, before: ((_ update: [String: Any?]) -> Void)? = nil, after: ((_ update: [String: Any?], _ error: Error?) -> Void)? = nil) {
        if let path = path ?? Bundle.main.path(forResource: "updates", ofType: "json") {
            let updater = DbUpdater(filePath: path, beforeUpdate: before, afterUpdate: after)
            updater.run()
        } else {
            #if DEBUG
            print("updates.json not found in main bundle")
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
}
