//
//  Database.swift
//  SqliteStore
//
//  Created by Aikyuichi on 10/9/19.
//  Copyright (c) 2022 aikyuichi <aikyu.sama@gmail.com>
//  Use of this source code is governed by a MIT license that can be found in the LICENSE file.
//

import Foundation
import SQLite3

public class Database {
    private let path: String
    private var sqlite: OpaquePointer? = nil
    
    public var lastInsertRowId: Int { Int(sqlite3_last_insert_rowid(self.sqlite)) }
    
    public var affectedRows: Int {
        if #available(iOS 15.4, *) {
            return Int(sqlite3_changes64(self.sqlite))
        } else {
            return Int(sqlite3_changes(self.sqlite))
        }
    }
    
    static public var sqliteVersion: String { String(cString: sqlite3_libversion()) }
    
    static internal func open(_ path: String, readonly: Bool = false) throws -> Database {
        let db = Database(path)
        try db.open(readonly: readonly)
        try? db.executeQuery("PRAGMA foreign_keys = ON")
        return db
    }
    
    static public func open(_ path: String, readonly: Bool = false, execute code: (Database) throws -> Void) throws {
        let db = try Database.open(path, readonly: readonly)
        defer { db.close() }
        try code(db)
    }
    
    public func attach(databaseAtPath path: String, withSchema schema: String) throws {
        if !checkSchemaAlreadyExists(schema: schema) {
            try executeQuery("ATTACH DATABASE '\(path)' AS \(schema)")
        }
    }
    
    public func detach(schema: String) throws {
        try executeQuery("DETACH DATABASE \(schema)")
    }
    
    public func beginTransaction() throws {
        try executeQuery("BEGIN TRANSACTION")
    }
    
    public func commit() {
        try? executeQuery("COMMIT")
    }
    
    public func rollBack() {
        try? executeQuery("ROLLBACK")
    }
    
    public func transaction(execute code: () throws -> Void) throws {
        do {
            try beginTransaction()
            try code()
            commit()
        } catch {
            rollBack()
            #if DEBUG
            print("Transaction rolled back")
            #endif
            throw error
        }
    }
    
    public func prepareStatement(_ query: String) throws -> Statement {
        guard let statement = Statement(sqlite: self.sqlite, query: query) else {
            throw sqliteError(query: query)
        }
        return statement
    }
    
    public func prepareStatement(_ query: String, execute code: (Statement) throws -> Void) throws {
        let stmt = try prepareStatement(query)
        defer { stmt.finalize() }
        try code(stmt)
    }
    
    public func executeQuery(_ query: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(self.sqlite, query, nil, nil, &error) != SQLITE_OK {
            if let error {
                let message = String(cString: error)
                sqlite3_free(error)
                throw sqliteError(message: message, query: query)
            }
        }
    }
    
    public func executeStatement(_ query: String, parameters: [Any?]) throws {
        try prepareStatement(query) { stmt in
            if let parameters = parameters as? [[String: Any?]] {
                for row in parameters {
                    try stmt.bind(parameters: row)
                    try stmt.step()
                    try stmt.reset()
                }
            } else if let parameters = parameters as? [[Any?]] {
                for row in parameters {
                    try stmt.bind(parameters: row)
                    try stmt.step()
                    try stmt.reset()
                }
            } else {
                try stmt.bind(parameters: parameters)
                try stmt.step()
            }
        }
    }
    
    public func executeStatement(_ query: String, parameters: [String: Any?]) throws {
        try prepareStatement(query) { stmt in
            try stmt.bind(parameters: parameters)
            try stmt.step()
        }
    }
    
    public func select(_ query: String, parameters: [Any?] = []) throws -> [[String: Any?]] {
        var result: [[String: Any?]] = []
        try prepareStatement(query) { stmt in
            try stmt.bind(parameters: parameters)
            while let row = stmt.fetch() {
                result.append(row)
            }
        }
        return result
    }
    
    public func select(_ query: String, parameters: [String: Any?]) throws -> [[String: Any?]] {
        var result: [[String: Any?]] = []
        try prepareStatement(query) { stmt in
            try stmt.bind(parameters: parameters)
            while let row = stmt.fetch() {
                result.append(row)
            }
        }
        return result
    }
    
    public func selectFirst(_ query: String, parameters: [Any?] = []) -> [String: Any?]? {
        return try? select(query, parameters: parameters).first
    }
    
    public func selectFirst(_ query: String, parameters: [String: Any?]) -> [String: Any?]? {
        return try? select(query, parameters: parameters).first
    }
    
    public func selectBool(_ query: String, parameters: [Any?] = []) -> Bool? {
        var scalar: Bool? = nil
        do {
            try prepareStatement(query) { stmt in
                try stmt.bind(parameters: parameters)
                if try stmt.step() {
                    scalar = stmt.getBool(forIndex: 0)
                }
            }
        } catch { }
        return scalar
    }
    
    public func selectBool(_ query: String, parameters: [String: Any?]) -> Bool? {
        var scalar: Bool? = nil
        do {
            try prepareStatement(query) { stmt in
                try stmt.bind(parameters: parameters)
                if try stmt.step() {
                    scalar = stmt.getBool(forIndex: 0)
                }
            }
        } catch { }
        return scalar
    }
    
    public func selectDouble(_ query: String, parameters: [Any?] = []) -> Double? {
        var scalar: Double? = nil
        do {
            try prepareStatement(query) { stmt in
                try stmt.bind(parameters: parameters)
                if try stmt.step() {
                    scalar = stmt.getDouble(forIndex: 0)
                }
            }
        } catch { }
        return scalar
    }
    
    public func selectDouble(_ query: String, parameters: [String: Any?]) -> Double? {
        var scalar: Double? = nil
        do {
            try prepareStatement(query) { stmt in
                try stmt.bind(parameters: parameters)
                if try stmt.step() {
                    scalar = stmt.getDouble(forIndex: 0)
                }
            }
        } catch { }
        return scalar
    }
    
    public func selectInt(_ query: String, parameters: [Any?] = []) -> Int? {
        var scalar: Int? = nil
        do {
            try prepareStatement(query) { stmt in
                try stmt.bind(parameters: parameters)
                if try stmt.step() {
                    scalar = stmt.getInt(forIndex: 0)
                }
            }
        } catch { }
        return scalar
    }
    
    public func selectInt(_ query: String, parameters: [String: Any?]) -> Int? {
        var scalar: Int? = nil
        do {
            try prepareStatement(query) { stmt in
                try stmt.bind(parameters: parameters)
                if try stmt.step() {
                    scalar = stmt.getInt(forIndex: 0)
                }
            }
        } catch { }
        return scalar
    }
    
    public func selectString(_ query: String, parameters: [Any?] = []) -> String? {
        var scalar: String? = nil
        do {
            try prepareStatement(query) { stmt in
                try stmt.bind(parameters: parameters)
                if try stmt.step() {
                    scalar = stmt.getString(forIndex: 0)
                }
            }
        } catch { }
        return scalar
    }
    
    public func selectString(_ query: String, parameters: [String: Any?]) -> String? {
        var scalar: String? = nil
        do {
            try prepareStatement(query) { stmt in
                try stmt.bind(parameters: parameters)
                if try stmt.step() {
                    scalar = stmt.getString(forIndex: 0)
                }
            }
        } catch { }
        return scalar
    }
    
    internal func close() {
        sqlite3_close(self.sqlite)
    }
    
    private init(_ path : String) {
        self.path = path
    }
    
    private func open(readonly: Bool = false) throws {
        let readMode = readonly ? SQLITE_OPEN_READONLY : SQLITE_OPEN_READWRITE
        if sqlite3_open_v2(self.path, &self.sqlite, readMode, nil) != SQLITE_OK {
            close()
            throw sqliteError()
        }
    }
    
    private func checkSchemaAlreadyExists(schema: String) -> Bool {
        let attachements = getAttachements()
        return attachements.contains(where: { $0["name"] as! String == schema })
    }
    
    private func sqliteError(message: String? = nil, query: String? = nil) -> SQLiteError {
        var message = message ?? String(cString: sqlite3_errmsg(self.sqlite))
        if let query {
            message.append("\n\(query)")
        }
        let error = SQLiteError(
            code: Int(sqlite3_errcode(self.sqlite)),
            message: message
        )
        #if DEBUG
        print(error)
        #endif
        return error
    }
}

// MARK: - PRAGMAS

extension Database {
    
    public func checkForeignKeys(ofSchema schema: String = "main") -> [[String: Any?]] {
        return (try? select("PRAGMA \(schema).foreign_key_check")) ?? []
    }
    
    public func checkForeignKeys(ofTable table: String, inSchema schema: String = "main") -> [[String: Any?]] {
        return (try? select("PRAGMA \(schema).foreign_key_check(\(table))")) ?? []
    }
    
    public func checkIntegrity(ofSchema schema: String = "main", limit: Int = 100, quick: Bool = false) -> [[String: Any?]] {
        if quick {
            return (try? select("PRAGMA \(schema).quick_check(\(limit)")) ?? []
        } else {
            return (try? select("PRAGMA \(schema).integrity_check(\(limit)")) ?? []
        }
    }
    
    public func checkIntegrity(ofTable table: String, inSchema schema: String = "main", quick: Bool = false) -> [[String: Any?]] {
        if quick {
            return (try? select("PRAGMA \(schema).quick_check(\(table)")) ?? []
        } else {
            return (try? select("PRAGMA \(schema).integrity_check(\(table)")) ?? []
        }
    }
    
    @discardableResult
    public func optimize(schema: String = "main", withMask mask: Int? = nil) -> [[String: Any?]] {
        return (try? select("PRAGMA \(schema).optimize\(mask != nil ? "(\(mask!))" : "")")) ?? []
    }
    
    public func getAttachements() -> [[String: Any?]] {
        return (try? select("PRAGMA database_list")) ?? []
    }
    
    public func getForeignKeys(ofTable table: String) -> [[String: Any?]] {
        return (try? select("PRAGMA foreign_key_list(\(table))")) ?? []
    }
    
    public func getIndexes(ofTable table: String, inSchema schema: String = "main") -> [[String: Any?]] {
        return (try? select("PRAGMA \(schema).index_list(\(table)")) ?? []
    }
    
    public func getInfo(ofIndex index: String, inSchema schema: String = "main")-> [[String: Any?]] {
        return (try? select("PRAGMA \(schema).index_info(\(index))")) ?? []
    }
    
    public func getInfo(ofTable table: String, inSchema schema: String = "main")-> [[String: Any?]] {
        return (try? select("PRAGMA \(schema).table_xinfo(\(table))")) ?? []
    }
    
    public func getTables(ofSchema schema: String = "main") -> [[String: Any?]] {
        return (try? select("PRAGMA \(schema).table_list")) ?? []
    }
    
    public func getUserVersion(ofSchema schema: String = "main") -> Int {
        return selectInt("PRAGMA \(schema).user_version") ?? 0
    }
    
    public func setUserVersion(_ version: Int, ofSchema schema: String = "main") {
        try? executeQuery("PRAGMA \(schema).user_version=\(version)")
    }
}
