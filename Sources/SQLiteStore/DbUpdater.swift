//
//  File.swift
//  SQLiteStore
//
//  Created by Luis Mosquera on 15/7/26.
//

import Foundation

struct DbUpdater {
    private let filePath: String
    private let beforeUpdate: ((_ update: [String: Any?]) -> Void)?
    private let afterUpdate: ((_ update: [String: Any?], _ error: Bool) -> Void)?
    
    init(filePath: String, beforeUpdate: ((_: [String : Any?]) -> Void)?, afterUpdate: ((_: [String : Any?], _: Bool) -> Void)?) {
        self.filePath = filePath
        self.beforeUpdate = beforeUpdate
        self.afterUpdate = afterUpdate
    }
    
    func run() {
        let updates = self.getUpdates()
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
    
    private func getUpdates() -> [UpdateItem] {
        var updates: [UpdateItem] = []
        do {
            if let data = try String(contentsOfFile: self.filePath).data(using: .utf8),
               let json = try JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] {
                let dbKeys = json.keys
                for dbKey in dbKeys {
                    if let versions = json[dbKey]!["versions"] as? [String: [String: Any]] {
                        let versionIds = versions.keys.sorted { Int($0)! < Int($1)! }
                        for versionId in versionIds {
                            if let update = UpdateItem(version: Int(versionId)!, dbKey: dbKey, json: versions[versionId]!) {
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
    
    private func executeUpdate(_ update: UpdateItem) -> Bool {
        if let dbAssets = try? DbStore.shared.getAsset(forKey: update.dbKey), dbAssets.fileExists {
            guard let db = try? Database.open(dbAssets.path) else {
                self.afterUpdate?(update.toDict(), true)
                return false
            }
            defer { db.close() }
            do {
                for attach in update.attachments {
                    let attachmentAsset = try DbStore.shared.getAsset(forKey: attach)
                    try db.attach(databaseAtPath: attachmentAsset.path, withSchema: attach)
                }
                if db.getUserVersion() < update.version {
                    self.beforeUpdate?(update.toDict())
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
                    self.afterUpdate?(update.toDict(), false)
                }
            } catch {
                if update.skipOnError {
                    db.setUserVersion(update.version)
                    if update.vacuum {
                        try? db.executeQuery("VACUUM")
                    }
                }
                self.afterUpdate?(update.toDict(), true)
                return false
            }
        }
        return true
    }
}

enum UpdateError: Error {
    case invalidFormat
    case invalidVersion
}

private struct UpdateItem {
    let version: Int
    let dbKey: String
    let commands: [String]
    let attachments: [String]
    let vacuum: Bool
    let optimize: Bool
    let skipOnError: Bool
    
    init?(version: Int, dbKey: String, json: [String: Any]) {
        guard let commands = json["commands"] as? [String] else {
            #if DEBUG
            print("updater: invalid format")
            #endif
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
