//
//  Statement.swift
//  SqliteStore
//
//  Created by Aikyuichi on 16/10/25.
//  Copyright (c) 2022 aikyuichi <aikyu.sama@gmail.com>
//  Use of this source code is governed by a MIT license that can be found in the LICENSE file.
//

import Foundation
import SQLite3

protocol Transaction {
    func rollback()
}

/// Wraps a compiled SQLite statement and provides a small API for binding values and reading results.
public class Statement {
    private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    private let sqlite: OpaquePointer?
    private let errorHandler: ((SQLiteError) -> Void)?
    private var sqliteStatement: OpaquePointer? = nil
    private var resultColumns: [String: Int] = [:]
    /// The trailing portion of the SQL that SQLite did not compile.
    public var uncompiledSql = ""
    
    /// The SQL source associated with the prepared statement.
    public var query: String {
        guard let sqliteStatement else { return "" }
        return String(cString: sqlite3_sql(sqliteStatement))
    }
    
    /// Returns the expanded SQL representation, if the platform exposes it.
    @available(iOS 10.0, *)
    public var expandedQuery: String {
        var expandedSql: String = ""
        guard let sqliteStatement else { return expandedSql }
        let cExpandedSql = sqlite3_expanded_sql(sqliteStatement)
        if let cExpandedSql {
            expandedSql = String(cString: cExpandedSql)
        }
        sqlite3_free(cExpandedSql)
        return expandedSql
    }
    
    /// Returns the normalized SQL representation, when available on the platform.
    @available(macOS 12.0, *)
    @available(iOS 15.0, *)
    public var normalizedQuery: String {
        guard let sqliteStatement else { return "" }
        return String(cString: sqlite3_normalized_sql(sqliteStatement))
    }
    
    /// The number of columns returned by the statement.
    public var columnCount: Int {
        guard let sqliteStatement else { return 0 }
        return Int(sqlite3_column_count(sqliteStatement))
    }
    
    init?(sqlite: OpaquePointer?, query: String, onError: ((SQLiteError) -> Void)? = nil) {
        var uncompiledSql: UnsafePointer<CChar>? = nil
        if sqlite3_prepare_v2(sqlite, query, -1, &self.sqliteStatement, &uncompiledSql) == SQLITE_OK {
            self.sqlite = sqlite
            self.errorHandler = onError
            if let uncompiledSql = uncompiledSql, strlen(uncompiledSql) > 0 {
                self.uncompiledSql = String(cString: uncompiledSql)
                print("warning: uncompiled sql - \(self.uncompiledSql)")
            }
        } else {
            return nil
        }
    }
    
    deinit {
        finalize()
    }
    
    /// Advances the statement to the next row and returns whether a row is available.
    @discardableResult
    public func step() throws -> Bool {
        var result = false
        let stepResult = sqlite3_step(sqliteStatement)
        if stepResult == SQLITE_ROW {
            result = true
            if self.resultColumns.isEmpty {
                for i in 0..<self.columnCount {
                    self.resultColumns[self.getColumnName(forIndex: i)] = i
                }
            }
        } else if stepResult != SQLITE_DONE {
            throw sqliteError(code: Int(stepResult))
        }
        return result
    }
    
    /// Resets the statement so it can be executed again, optionally clearing bound values.
    public func reset(includingBindings: Bool = false) throws {
        if includingBindings {
            sqlite3_clear_bindings(self.sqliteStatement)
        }
        if sqlite3_reset(self.sqliteStatement) != SQLITE_OK {
            throw sqliteError()
        }
    }
    
    /// Finalizes the underlying SQLite statement and releases its resources.
    public func finalize() {
        sqlite3_finalize(self.sqliteStatement)
        self.sqliteStatement = nil
    }
    
    /// Binds positional values to the prepared statement.
    public func bind(parameters: [Any?]) throws {
        for i in 0..<parameters.count {
            let parameter = parameters[i]
            try bind(value: parameter, forIndex: i + 1)
        }
    }
    
    /// Binds named values to the prepared statement using SQLite parameter names.
    public func bind(parameters: [String: Any?]) throws {
        for parameter in parameters {
            try bind(value: parameter.value, forName: parameter.key)
        }
    }
    
    /// Binds an integer value at a positional index.
    public func bind(int value: Int?, forIndex index: Int) throws {
        if let value = value {
            if sqlite3_bind_int64(self.sqliteStatement, Int32(index), Int64(value)) != SQLITE_OK {
                try bindFailed()
            }
        } else {
            bindNULL(forIndex: index)
        }
    }
    
    /// Binds a string value at a positional index.
    public func bind(string value: String?, forIndex index: Int) throws {
        if let stringValue = value {
            if sqlite3_bind_text(self.sqliteStatement, Int32(index), (stringValue as NSString).utf8String, -1, nil) != SQLITE_OK {
                try bindFailed()
            }
        } else {
            bindNULL(forIndex: index)
        }
    }
    
    /// Binds a floating-point value at a positional index.
    public func bind(double value: Double?, forIndex index: Int) throws {
        if let value = value {
            if sqlite3_bind_double(self.sqliteStatement, Int32(index), value) != SQLITE_OK {
                try bindFailed()
            }
        } else {
            bindNULL(forIndex: index)
        }
    }
    
    /// Binds a boolean value at a positional index.
    public func bind(bool value: Bool?, forIndex index: Int) throws {
        if let value = value {
            if sqlite3_bind_int(self.sqliteStatement, Int32(index), value ? 1 : 0) != SQLITE_OK {
                try bindFailed()
            }
        } else {
            bindNULL(forIndex: index)
        }
    }
    
    /// Binds a blob value at a positional index.
    public func bind(data value: Data?, forIndex index: Int) throws {
        if let value = value {
            let data = value as NSData
            if sqlite3_bind_blob(self.sqliteStatement, Int32(index), data.bytes, Int32(data.length), SQLITE_TRANSIENT) != SQLITE_OK {
                try bindFailed()
            }
        } else {
            bindNULL(forIndex: index)
        }
    }
    
    /// Binds a value based on its runtime type at a positional index.
    public func bind(value: Any?, forIndex index: Int) throws {
        switch value {
        case let stringValue as String?:
            try bind(string: stringValue, forIndex: index)
        case let integerValue as Int?:
            try bind(int: integerValue, forIndex: index)
        case let doubleValue as Double?:
            try bind(double: doubleValue, forIndex: index)
        case let boolValue as Bool?:
            try bind(bool: boolValue, forIndex: index)
        case let dataValue as Data?:
            try bind(data: dataValue, forIndex: index)
        default:
            bindNULL(forIndex: index)
        }
    }
    
    /// Binds an integer value to the parameter matching the supplied name.
    public func bind(int value: Int?, forName name: String) throws {
        let index = getBindIndex(forName: name)
        try bind(int: value, forIndex: index)
    }
    
    /// Binds a string value to the parameter matching the supplied name.
    public func bind(string value: String?, forName name: String) throws {
        let index = getBindIndex(forName: name)
        try bind(string: value, forIndex: index)
    }
    
    /// Binds a floating-point value to the parameter matching the supplied name.
    public func bind(double value: Double?, forName name: String) throws {
        let index = getBindIndex(forName: name)
        try bind(double: value, forIndex: index)
    }
    
    /// Binds a boolean value to the parameter matching the supplied name.
    public func bind(bool value: Bool?, forName name: String) throws {
        let index = getBindIndex(forName: name)
        try bind(bool: value, forIndex: index)
    }
    
    /// Binds a blob value to the parameter matching the supplied name.
    public func bind(data value: Data?, forName name: String) throws {
        let index = getBindIndex(forName: name)
        try bind(data: value, forIndex: index)
    }
    
    /// Binds a value based on its runtime type to the matching named parameter.
    public func bind(value: Any?, forName name: String) throws {
        let index = getBindIndex(forName: name)
        try bind(value: value, forIndex: index)
    }
    
    /// Fetches the next row as a dictionary keyed by column name.
    public func fetch() -> [String: Any?]? {
        if (try? step()) ?? false {
            var result: [String: Any?] = [:]
            for i in 0..<self.columnCount {
                let columnName = getColumnName(forIndex: i)
                result[columnName] = getValue(forIndex: i)
            }
            return result
        }
        return nil
    }
    
    /// Reads an integer value from the specified column index in the current row.
    public func getInt(forIndex index: Int) -> Int? {
        if isColumnNULL(forIndex: index) {
            return nil
        } else {
            return Int(sqlite3_column_int64(self.sqliteStatement, Int32(index)))
        }
    }
    
    /// Reads a string value from the specified column index in the current row.
    public func getString(forIndex index: Int) -> String? {
        if isColumnNULL(forIndex: index) {
            return nil
        } else {
            return String(cString: sqlite3_column_text(self.sqliteStatement, Int32(index)))
        }
    }
    
    /// Reads a floating-point value from the specified column index in the current row.
    public func getDouble(forIndex index: Int) -> Double? {
        if isColumnNULL(forIndex: index) {
            return nil
        } else {
            return sqlite3_column_double(self.sqliteStatement, Int32(index))
        }
    }
    
    /// Reads a boolean value from the specified column index in the current row.
    public func getBool(forIndex index: Int) -> Bool? {
        if isColumnNULL(forIndex: index) {
            return nil
        } else {
            return Int(sqlite3_column_int64(self.sqliteStatement, Int32(index))) != 0
        }
    }
    
    /// Reads a blob value from the specified column index in the current row.
    public func getData(forIndex index: Int) -> Data? {
        if isColumnNULL(forIndex: index) {
            return nil
        } else {
            let length = sqlite3_column_bytes(self.sqliteStatement, Int32(index))
            return Data(bytes: sqlite3_column_blob(self.sqliteStatement, Int32(index)), count: Int(length))
        }
    }
    
    /// Reads the value from the supplied column index using the column's SQLite type.
    public func getValue(forIndex index: Int) -> Any? {
        let dataType = sqlite3_column_type(self.sqliteStatement, Int32(index))
        switch dataType {
        case SQLITE_INTEGER:
            return getInt(forIndex: index)
        case SQLITE_FLOAT:
            return getDouble(forIndex: index)
        case SQLITE_TEXT:
            return getString(forIndex: index)
        case SQLITE_BLOB:
            return getData(forIndex: index)
        case SQLITE_NULL:
            return nil
        default:
            return nil
        }
    }
    
    /// Reads an integer value from the column matching the supplied name.
    public func getInt(forName name: String) -> Int? {
        if let index = self.resultColumns[name] {
            return getInt(forIndex: index)
        } else {
            return nil
        }
    }
    
    /// Reads a string value from the column matching the supplied name.
    public func getString(forName name: String) -> String? {
        if let index = self.resultColumns[name] {
            return getString(forIndex: index)
        } else {
            return nil
        }
    }
    
    /// Reads a floating-point value from the column matching the supplied name.
    public func getDouble(forName name: String) -> Double? {
        if let index = self.resultColumns[name] {
            return getDouble(forIndex: index)
        } else {
            return nil
        }
    }
    
    /// Reads a boolean value from the column matching the supplied name.
    public func getBool(forName name: String) -> Bool? {
        if let index = self.resultColumns[name] {
            return getBool(forIndex: index)
        } else {
            return nil
        }
    }
    
    /// Reads a blob value from the column matching the supplied name.
    public func getData(forName name: String) -> Data? {
        if let index = self.resultColumns[name] {
            return getData(forIndex: index)
        } else {
            return nil
        }
    }
    
    /// Reads the value from the column matching the supplied name.
    public func getValue(forName name: String) -> Any? {
        if let index = self.resultColumns[name] {
            return getValue(forIndex: index)
        }
        return nil
    }
    
    private func getBindIndex(forName name: String) -> Int {
        return Int(sqlite3_bind_parameter_index(self.sqliteStatement, name.cString(using: .utf8)))
    }
    
    private func getColumnName(forIndex index: Int) -> String {
        return String(cString: sqlite3_column_name(self.sqliteStatement, Int32(index)))
    }
    
    private func isColumnNULL(forIndex index: Int) -> Bool {
        sqlite3_column_type(self.sqliteStatement, Int32(index)) == SQLITE_NULL
    }
    
    private func bindNULL(forIndex index: Int) {
        sqlite3_bind_null(self.sqliteStatement, Int32(index))
    }
    
    private func bindFailed() throws {
        throw sqliteError()
    }
    
    private func sqliteError(code: Int? = nil) -> SQLiteError {
        var message = String(cString: sqlite3_errmsg(self.sqlite))
        if self.sqliteStatement == nil {
            message = "\nstatement is already finalized"
        }
        var query = self.expandedQuery
        if query.isEmpty {
            query = self.query
        }
        let error = SQLiteError(
            code: code ?? Int(sqlite3_errcode(self.sqlite)),
            message: message,
            query: query,
        )
        #if DEBUG
        print(error)
        #endif
        self.errorHandler?(error)
        return error
    }
}
