//
//  DbStore.swift
//  SqliteStore
//
//  Created by Aikyuichi on 16/10/25.
//  Copyright (c) 2022 aikyuichi <aikyu.sama@gmail.com>
//  Use of this source code is governed by a MIT license that can be found in the LICENSE file.
//

import Foundation

class DbStore {
    static let shared = DbStore()
    
    private var assets: [String: DbAsset] = [:]
    private var databases: [String: Database] = [:]
    private var defaultDbKey = ""
    
    private init() { }
    
    func add(asset: DbAsset, forKey key: String, default defaultDb: Bool) {
        self.assets[key] = asset
        if defaultDb {
            self.defaultDbKey = key
        }
    }
    
    func getAsset(forKey dbKey: String) throws -> DbAsset {
        guard let asset = self.assets[dbKey] else {
            throw DbStoreError(message: "\"\(dbKey)\" is not registered.")
        }
        return asset
    }
    
    func getDatabase(forKey dbKey: String) throws -> Database {
        let dbAsset = try self.getAsset(forKey: dbKey)
        if self.databases[dbKey] == nil {
            if !dbAsset.fileExists {
                throw DbStoreError(message: "file not found: \(dbAsset.path)")
            }
            let db = try Database.open(dbAsset.path, readonly: dbAsset.readonly)
            for (schema, dbKey) in dbAsset.attachements {
                let attachementAsset = try self.getAsset(forKey: dbKey)
                try db.attach(databaseAtPath: attachementAsset.path, withSchema: schema)
            }
            self.databases[dbKey] = db
        }
        return self.databases[dbKey]!
    }
    
    func getDefaultDbKey() -> String {
        if self.defaultDbKey.isEmpty, self.assets.keys.count > 0, let key = self.assets.keys.first {
            self.defaultDbKey = key
        }
        return self.defaultDbKey
    }
    
    func remove(dbKey: String) {
        self.assets.removeValue(forKey: dbKey)
        self.databases[dbKey]?.close()
        self.databases.removeValue(forKey: dbKey)
    }
    
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
}

struct DbAsset {
    let path: String
    let attachements: [String: String]
    let readonly: Bool
    
    var fileExists: Bool {
        return FileManager.default.fileExists(atPath: self.path)
    }
}
