//
//  SqliteStore.swift
//  SqliteStore
//
//  Created by Aikyuichi on 10/9/19.
//  Copyright (c) 2022 aikyuichi <aikyu.sama@gmail.com>
//

import Foundation

extension Database {
    static public func register(path: String, forKey key: String, attachements: [String: String] = [:], default defaultDb: Bool = false) {
        Store.shared.add(dbKey: key, dbPath: path, attachements: attachements, defaultDb: defaultDb)
    }
    
    #if os(iOS)
    static public func register(fromMainBundleWithName name: String, forKey key: String, attachements: [String: String] = [:], copyToDocumentDirectory copy: Bool = false, default defaultDb: Bool = false) {
        let url = NSURL(fileURLWithPath: name)
        let dbPath = Bundle.main.path(forResource: url.deletingPathExtension?.lastPathComponent, ofType: url.pathExtension)!
        if copy {
            if let documentPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first {
                let dbPathTo = (documentPath as NSString).appendingPathComponent(name)
                if !FileManager.default.fileExists(atPath: dbPathTo) {
                    try! FileManager.default.copyItem(atPath: dbPath, toPath: dbPathTo)
                }
                self.register(path: dbPathTo, forKey: key, attachements: attachements, default: defaultDb)
            }
        } else {
            self.register(path: dbPath, forKey: key, attachements: attachements, default: defaultDb)
        }
    }
    #endif
    
    #if os(iOS)
    static public func register(fromDocumentDirectoryWithName name: String, forKey key: String, attachements: [String: String] = [:], default defaultDb: Bool = false) {
        if let documentPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first {
            let dbPath = (documentPath as NSString).appendingPathComponent(name)
            self.register(path: dbPath, forKey: key, attachements: attachements, default: defaultDb)
        }
    }
    #endif
    
    static public func unregister(forkey key: String) {
        Store.shared.remove(dbKey: key)
    }
    
    static public func get() -> Database? {
        let key = Store.shared.getDefaultDbKey()
        return Store.shared.get(dbKey: key)
    }
    
    static public func get(forKey key: String) -> Database? {
        return Store.shared.get(dbKey: key)
    }
    
    static public func open(readonly: Bool = false, execute code: (Database) throws -> Void) throws {
        let key = Store.shared.getDefaultDbKey()
        try Database.open(forKey: key, readonly: readonly, execute: code)
    }
    
    static public func open(forKey key: String, readonly: Bool = false, execute code: (Database) throws -> Void) throws {
        let path = Store.shared.getPath(dbKey: key)
        let attachements = Store.shared.getAttachements(dbKey: key)
        let db = try Database.open(path, readonly: readonly)
        for (schema, dbKey) in attachements {
            try db.attach(databaseAtPath: Store.shared.getPath(dbKey: dbKey), withSchema: schema)
        }
        try code(db)
        db.close()
    }
    
    static public func closeAll() {
        Store.shared.close()
    }
}

extension Database {
    static public func update(path: String? = nil) throws {
        if let path = path ?? Bundle.main.path(forResource: "updates", ofType: "json") {
            let updates = self.getUpdates(filename: path)
            if updates.isEmpty {
                return
            }
            for update in updates {
                if !(try self.executeUpdate(update)) {
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
    
    static private func executeUpdate(_ update: DbUpdate) throws -> Bool {
        var result = false
        if self.databaseExists(forKey: update.dbKey) {
            try Database.open(forKey: update.dbKey) { db in
                if db.userVersion < update.version {
                    try db.transaction {
                        for attach in update.attachments {
                            try db.attach(databaseAtPath: Store.shared.getPath(dbKey: attach), withSchema: attach)
                        }
                        for command in update.commands {
                            let stmt = try! db.prepareStatement(String(command))
                            try stmt.step()
                            stmt.finalize()
                            result = !stmt.failed
                            if !result {
                                break
                            }
                        }
                    }
                    if result || update.skipOnError {
                        try db.executeQuery("PRAGMA user_version = \(update.version)")
                        if update.vacuum {
                            try db.executeQuery("VACUUM")
                        }
                    }
                } else {
                    result = true
                }
            }
        }
        return result
    }
    
    static private func databaseExists(forKey key: String) -> Bool {
        let dbPath = Store.shared.getPath(dbKey: key)
        if !dbPath.isEmpty {
            return FileManager.default.fileExists(atPath: dbPath)
        }
        return false
    }
}

private struct DbUpdate {
    let version: Int
    let dbKey: String
    let commands: [String]
    let attachments: [String]
    let vacuum: Bool
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
        self.skipOnError = json["skipOnError"] as? Bool ?? false
        
    }
}
