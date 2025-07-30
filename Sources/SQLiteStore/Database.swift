//
//  Database.swift
//  SqliteStore
//
//  Created by Aikyuichi on 10/9/19.
//  Copyright (c) 2022 aikyuichi <aikyu.sama@gmail.com>
//

import Foundation
import SQLite3

public class Database {
    private let path: String
    private var sqlite: OpaquePointer? = nil
    private var isOpen = false
    private var openTransaction = false
    private var rollbackTransaction = false
    
    public var lastInsertRowId: Int {
        Int(sqlite3_last_insert_rowid(self.sqlite))
    }
    
    public var userVersion: Int {
        var version = 0
        try? prepareStatement("PRAGMA user_version") { stmt in
            if try stmt.step() {
                version = stmt.getInt(forIndex: 0)!
            }
        }
        return version
    }
    
    static internal func open(_ path: String, readonly: Bool = false) throws -> Database {
        let db = Database(path)
        try db.open(readonly: readonly)
        return db
    }
    
    static public func open(_ path: String, readonly: Bool = false, execute code: (Database) throws -> Void) throws {
        let db = try Database.open(path, readonly: readonly)
        try code(db)
        db.close()
    }
    
    public func attach(databaseAtPath path: String, withSchema schema: String) throws {
        if !(try checkSchemaAlreadyExists(schema: schema)) {
            try executeQuery("ATTACH DATABASE '\(path)' AS \(schema)")
        }
    }
    
    public func detach(schema: String) throws {
        try executeQuery("DETACH DATABASE \(schema)")
    }
    
    public func transaction(execute code: () throws -> Void) throws {
        try executeQuery("BEGIN TRANSACTION")
        self.openTransaction = true
        try code()
        if self.rollbackTransaction {
            try executeQuery("ROLLBACK")
            #if DEBUG
            print("Rollback transaction")
            #endif
        } else {
            try executeQuery("COMMIT")
        }
        self.openTransaction = false
        self.rollbackTransaction = false
    }
    
    public func prepareStatement(_ query: String) throws -> Statement {
        guard let statement = Statement(sqlite: self.sqlite, query: query) else {
            throw sqliteError(query: query)
        }
        if self.openTransaction {
            statement.transactionDelegate = self
        }
        return statement
    }
    
    public func prepareStatement(_ query: String, execute code: (Statement) throws -> Void) throws {
        let stmt = try prepareStatement(query)
        defer {
            stmt.finalize()
        }
        try code(stmt)
    }
    
    public func executeQuery(_ query: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(self.sqlite, query, nil, nil, &error) != SQLITE_OK {
            self.rollbackTransaction = true
            if let error {
                throw sqliteError(message: String(cString: error), query: query)
            }
            sqlite3_free(error)
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
        var result: [[String: Any]] = []
        try prepareStatement(query) { stmt in
            try stmt.bind(parameters: parameters)
            while let row = stmt.fetch() {
                result.append(row)
            }
        }
        return result
    }
    
    public func select(_ query: String, parameters: [String: Any?]) throws -> [[String: Any?]] {
        var result: [[String: Any]] = []
        try prepareStatement(query) { stmt in
            try stmt.bind(parameters: parameters)
            while let row = stmt.fetch() {
                result.append(row)
            }
        }
        return result
    }
    
    public func selectFirst(_ query: String, parameters: [Any?] = []) throws -> [String: Any?]? {
        return try select(query, parameters: parameters).first
    }
    
    public func selectFirst(_ query: String, parameters: [String: Any?]) throws -> [String: Any?]? {
        return try select(query, parameters: parameters).first
    }
    
    public func selectBool(_ query: String, parameters: [Any?] = []) throws -> Bool? {
        var scalar: Bool? = nil
        try prepareStatement(query) { stmt in
            try stmt.bind(parameters: parameters)
            if try stmt.step() {
                scalar = stmt.getBool(forIndex: 0)
            }
        }
        return scalar
    }
    
    public func selectBool(_ query: String, parameters: [String: Any?]) throws -> Bool? {
        var scalar: Bool? = nil
        try prepareStatement(query) { stmt in
            try stmt.bind(parameters: parameters)
            if try stmt.step() {
                scalar = stmt.getBool(forIndex: 0)
            }
        }
        return scalar
    }
    
    public func selectDouble(_ query: String, parameters: [Any?] = []) throws -> Double? {
        var scalar: Double? = nil
        try prepareStatement(query) { stmt in
            try stmt.bind(parameters: parameters)
            if try stmt.step() {
                scalar = stmt.getDouble(forIndex: 0)
            }
        }
        return scalar
    }
    
    public func selectDouble(_ query: String, parameters: [String: Any?]) throws -> Double? {
        var scalar: Double? = nil
        try prepareStatement(query) { stmt in
            try stmt.bind(parameters: parameters)
            if try stmt.step() {
                scalar = stmt.getDouble(forIndex: 0)
            }
        }
        return scalar
    }
    
    public func selectInt(_ query: String, parameters: [Any?] = []) throws -> Int? {
        var scalar: Int? = nil
        try prepareStatement(query) { stmt in
            try stmt.bind(parameters: parameters)
            if try stmt.step() {
                scalar = stmt.getInt(forIndex: 0)
            }
        }
        return scalar
    }
    
    public func selectInt(_ query: String, parameters: [String: Any?]) throws -> Int? {
        var scalar: Int? = nil
        try prepareStatement(query) { stmt in
            try stmt.bind(parameters: parameters)
            if try stmt.step() {
                scalar = stmt.getInt(forIndex: 0)
            }
        }
        return scalar
    }
    
    public func selectString(_ query: String, parameters: [Any?] = []) throws -> String? {
        var scalar: String? = nil
        try prepareStatement(query) { stmt in
            try stmt.bind(parameters: parameters)
            if try stmt.step() {
                scalar = stmt.getString(forIndex: 0)
            }
        }
        return scalar
    }
    
    public func selectString(_ query: String, parameters: [String: Any?]) throws -> String? {
        var scalar: String? = nil
        try prepareStatement(query) { stmt in
            try stmt.bind(parameters: parameters)
            if try stmt.step() {
                scalar = stmt.getString(forIndex: 0)
            }
        }
        return scalar
    }
    
    internal func close() {
        sqlite3_close(self.sqlite)
        self.isOpen = false
    }
    
    private init(_ path : String) {
        self.path = path
    }
    
    private func open(readonly: Bool = false) throws {
        if readonly {
            if sqlite3_open_v2(self.path, &self.sqlite, SQLITE_OPEN_READONLY, nil) != SQLITE_OK {
                throw sqliteError()
            }
        } else {
            if sqlite3_open(self.path, &self.sqlite) != SQLITE_OK {
                throw sqliteError()
            }
        }
        self.isOpen = true
    }
    
    private func checkSchemaAlreadyExists(schema: String) throws -> Bool {
        return try selectBool("SELECT 1 FROM pragma_database_list WHERE name = ?", parameters: [schema]) ?? false
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

extension Database: Transaction {
    func rollback() {
        self.rollbackTransaction = true
    }
}
