//
//  DbStore.swift
//  SqliteStore
//
//  Created by Aikyuichi on 16/10/25.
//  Copyright (c) 2022 aikyuichi <aikyu.sama@gmail.com>
//  Use of this source code is governed by a MIT license that can be found in the LICENSE file.
//

import Foundation

/// Central registry for database assets and their open instances.
class DbStore {
    static let shared = DbStore()
    
    private var assets: [String: DbAsset] = [:]
    private var databases: [String: Database] = [:]
    private var defaultDbKey = ""
    private var errorHandler: ((SQLiteError) -> Void)?
    
    private init() { }
    
    /// Registers a database asset under a unique key and optionally marks it as default.
    func add(asset: DbAsset, forKey key: String, default defaultDb: Bool) {
        self.assets[key] = asset
        if defaultDb {
            self.defaultDbKey = key
        }
    }
    
    /// Returns the registered asset for a key.
    func getAsset(forKey dbKey: String) throws -> DbAsset {
        guard let asset = self.assets[dbKey] else {
            throw DbStoreError(message: "\"\(dbKey)\" is not registered.")
        }
        return asset
    }
    
    /// Returns a cached or newly opened database instance for the provided key.
    func getDatabase(forKey dbKey: String) throws -> Database {
        let dbAsset = try self.getAsset(forKey: dbKey)
        if self.databases[dbKey] == nil {
            if !dbAsset.fileExists {
                throw DbStoreError(message: "file not found: \(dbAsset.path)")
            }
            let db = try Database.open(dbAsset.path, readonly: dbAsset.readonly, onError: self.errorHandler)
            for (schema, dbKey) in dbAsset.attachements {
                if let attachementAsset = try? self.getAsset(forKey: dbKey) {
                    try db.attach(databaseAtPath: attachementAsset.path, withSchema: schema)
                }
            }
            self.databases[dbKey] = db
        }
        return self.databases[dbKey]!
    }
    
    /// Returns the default database key, selecting the first registered database if needed.
    func getDefaultDbKey() -> String {
        if self.defaultDbKey.isEmpty, self.assets.keys.count > 0, let key = self.assets.keys.first {
            self.defaultDbKey = key
        }
        return self.defaultDbKey
    }
    
    /// Removes a database registration and closes its active connection, if any.
    func remove(dbKey: String) {
        self.assets.removeValue(forKey: dbKey)
        self.databases[dbKey]?.close()
        self.databases.removeValue(forKey: dbKey)
    }
    
    /// Closes the provided database or all tracked databases when no key is given.
    func close(dbKey: String? = nil) {
        if let dbKey {
            self.databases[dbKey]?.close()
            self.databases.removeValue(forKey: dbKey)
        } else {
            for dbKey in self.databases.keys {
                self.databases[dbKey]?.close()
                self.databases.removeValue(forKey: dbKey)
            }
        }
    }
    
    /// Registers the shared error handler used when opening or querying a database.
    func setErrorHandler(_ handler: @escaping (SQLiteError) -> Void) {
        self.errorHandler = handler
    }
}

/// Describes a SQLite database file and any attached schemas registered with the store.
struct DbAsset {
    let path: String
    let attachements: [String: String]
    let readonly: Bool
    
    var fileExists: Bool {
        return FileManager.default.fileExists(atPath: self.path)
    }
}
