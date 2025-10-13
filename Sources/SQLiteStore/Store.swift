//
//  Store.swift
//  SqliteStore
//
//  Created by Aikyuichi on 10/9/19.
//  Copyright (c) 2022 aikyuichi <aikyu.sama@gmail.com>
//

import Foundation

class Store {
    static let shared = Store()
    
    private var assets: [String: (dbPath: String, attachements: [String: String], readonly: Bool)] = [:]
    private var databases: [String: Database] = [:]
    private var defaultDbKey = ""
    
    private init() { }
    
    func add(dbKey: String, dbPath: String, attachements: [String: String], readonlyDb: Bool, defaultDb: Bool) {
        self.assets[dbKey] = (dbPath: dbPath, attachements: attachements, readonlyDb)
        if defaultDb {
            self.defaultDbKey = dbKey
        }
    }
    
    func get(dbKey: String) -> Database? {
        if self.databases[dbKey] == nil {
            if let db = try? Database.open(self.assets[dbKey]?.dbPath ?? "", readonly: self.assets[dbKey]?.readonly ?? false) {
                let attachements = getAttachements(dbKey: dbKey)
                for (schema, dbKey) in attachements {
                    try? db.attach(databaseAtPath: getPath(dbKey: dbKey), withSchema: schema)
                }
                self.databases[dbKey] = db
            }
        }
        return self.databases[dbKey]
    }
    
    func getPath(dbKey: String) -> String {
        return self.assets[dbKey]?.dbPath ?? ""
    }
    
    func getAttachements(dbKey: String) -> [String: String] {
        return self.assets[dbKey]?.attachements ?? [:]
    }
    
    func getDefaultDbKey() -> String {
        if self.defaultDbKey.isEmpty, self.assets.keys.count > 0, let key = self.assets.keys.first {
            self.defaultDbKey = key
        }
        return self.defaultDbKey
    }
    
    func remove(dbKey: String) {
        self.assets.removeValue(forKey: dbKey)
        if let db = self.databases[dbKey] {
            db.close()
        }
        self.databases.removeValue(forKey: dbKey)
    }
    
    func close() {
        for db in self.databases.values {
            db.close()
        }
    }
}
