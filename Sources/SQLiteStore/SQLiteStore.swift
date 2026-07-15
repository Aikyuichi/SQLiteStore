//
//  SqliteStore.swift
//  SqliteStore
//
//  Created by Aikyuichi on 16/10/25.
//  Copyright (c) 2022 aikyuichi <aikyu.sama@gmail.com>
//  Use of this source code is governed by a MIT license that can be found in the LICENSE file.
//

import Foundation

extension Database {    
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
    static public func register(fromDocumentDirectoryWithName name: String, forKey key: String, attachements: [String: String] = [:], readonly: Bool = false, default defaultDb: Bool = false) {
        if let documentPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first {
            let dbPath = (documentPath as NSString).appendingPathComponent(name)
            self.register(path: dbPath, forKey: key, attachements: attachements, readonly: readonly, default: defaultDb)
        }
    }
    #endif
    
    static public func unregister(forkey key: String) {
        DbStore.shared.remove(dbKey: key)
    }
    
    static public func get() throws -> Database {
        let key = DbStore.shared.getDefaultDbKey()
        return try get(forKey: key)
    }
    
    static public func get(forKey key: String) throws -> Database {
        return try DbStore.shared.getDatabase(forKey: key)
    }
    
    static public func open(readonly: Bool = false, execute code: (_ db: Database) throws -> Void) throws {
        let key = DbStore.shared.getDefaultDbKey()
        try Database.open(forKey: key, readonly: readonly, execute: code)
    }
    
    static public func open(forKey key: String, readonly: Bool = false, execute code: (_ db: Database) throws -> Void) throws {
        let dbAsset = try DbStore.shared.getAsset(forKey: key)
        let db = try Database.open(dbAsset.path, readonly: readonly)
        defer { db.close() }
        for (schema, dbKey) in dbAsset.attachements {
            let attachementAsset = try DbStore.shared.getAsset(forKey: dbKey)
            try db.attach(databaseAtPath: attachementAsset.path, withSchema: schema)
        }
        try code(db)
    }
    
    static public func update(path: String? = nil, before: ((_ update: [String: Any?]) -> Void)? = nil, after: ((_ update: [String: Any?], _ error: Bool) -> Void)? = nil) {
        if let path = path ?? Bundle.main.path(forResource: "updates", ofType: "json") {
            let updater = DbUpdater(filePath: path, beforeUpdate: before, afterUpdate: after)
            updater.run()
        } else {
            #if DEBUG
            print("updates.json not found in main bundle")
            #endif
        }
    }
    
    static public func close(forKey key: String? = nil) {
        DbStore.shared.close(dbKey: key)
    }
    
    static public func onError(callback: @escaping (SQLiteError) -> Void) {
        Self.onErrorCallback = callback
    }
}
