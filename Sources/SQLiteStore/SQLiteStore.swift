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
    
    static public func close(forKey key: String? = nil) {
        DbStore.shared.close(dbKey: key)
    }
    
    static public func onError(callback: @escaping (SQLiteError) -> Void) {
        Self.onErrorCallback = callback
    }
}

extension Database {
    static public func update(path: String? = nil, before: ((_ update: Dictionary<String, Any?>) -> Void)? = nil, after: ((_ update: Dictionary<String, Any?>, _ error: Bool) -> Void)? = nil) {
        if let path = path ?? Bundle.main.path(forResource: "updates", ofType: "json") {
            let updates = self.getUpdates(filename: path)
            if updates.isEmpty {
                return
            }
            for update in updates {
                let result = self.executeUpdate(update, before: before, after: after)
                if !result {
                    if update.skipOnError {
                        print("update failed but skipped: \(update)")
                    } else {
                        print("update failed: \(update)")
                        break
                    }
                }
            }
        } else {
            print("updates.json not found in main bundle")
        }
    }
    
    static private func getUpdates(filename: String) -> [DbUpdate] {
        var updates: [DbUpdate] = []
        do {
            if let data = try String(contentsOfFile: filename).data(using: .utf8),
               let json = try JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] {
                let dbKeys = json.keys
                for dbKey in dbKeys {
                    if let versions = json[dbKey]!["versions"] as? [String: [String: Any]] {
                        let versionIds = versions.keys.sorted { Int($0)! < Int($1)! }
                        for versionId in versionIds {
                            if let update = DbUpdate(version: Int(versionId)!, dbKey: dbKey, json: versions[versionId]!) {
                                updates.append(update)
                            } else {
                                break
                            }
                        }
                    }
                }
            }
        } catch {
            print(error)
        }
        return updates
    }
    
    static private func executeUpdate(_ update: DbUpdate, before: ((_ update: Dictionary<String, Any?>) -> Void)?, after: ((_ update: Dictionary<String, Any?>, _ error: Bool) -> Void)?) -> Bool {
        if let dbAssets = try? DbStore.shared.getAsset(forKey: update.dbKey), dbAssets.fileExists {
            guard let db = try? Database.open(dbAssets.path) else {
                after?(update.toDict(), false)
                return false
            }
            defer { db.close() }
            do {
                for attach in update.attachments {
                    let attachmentAsset = try DbStore.shared.getAsset(forKey: attach)
                    try db.attach(databaseAtPath: attachmentAsset.path, withSchema: attach)
                }
                if db.getUserVersion() < update.version {
                    before?(update.toDict())
                    try db.transaction {
                        for command in update.commands {
                            try db.executeQuery(command)
                        }
                        try db.setUserVersion(update.version)
                    }
                    if update.vacuum {
                        try db.executeQuery("VACUUM")
                    }
                    if update.optimize {
                        try db.optimize()
                    }
                    after?(update.toDict(), true)
                }
            } catch {
                if update.skipOnError {
                    try? db.setUserVersion(update.version)
                    if update.vacuum {
                        try? db.executeQuery("VACUUM")
                    }
                }
                after?(update.toDict(), false)
                return false
            }
        }
        return true
    }
}

private struct DbUpdate {
    let version: Int
    let dbKey: String
    let commands: [String]
    let attachments: [String]
    let vacuum: Bool
    let optimize: Bool
    let skipOnError: Bool
    
    init?(version: Int, dbKey: String, json: [String: Any]) {
        guard let commands = json["commands"] as? [String] else {
            print("updater: invalid format")
            return nil
        }
        self.version = version
        self.dbKey = dbKey
        self.commands = commands
        self.attachments = json["attachments"] as? [String] ?? []
        self.vacuum = json["vacuum"] as? Bool ?? false
        self.optimize = json["optimize"] as? Bool ?? false
        self.skipOnError = json["skipOnError"] as? Bool ?? false
        
    }
    
    func toDict() -> [String: Any] {
        return [
            "version": version,
            "dbKey": dbKey,
            "commands": commands,
            "attachments": attachments,
            "vacuum": vacuum,
            "optimize": optimize,
            "skipOnError": skipOnError
        ]
    }
}
