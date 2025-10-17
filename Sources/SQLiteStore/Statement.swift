//
//  Statement.swift
//  SqliteStore
//
//  Created by Aikyuichi on 10/9/19.
//  Copyright (c) 2022 aikyuichi <aikyu.sama@gmail.com>
//

import Foundation
import SQLite3

protocol Transaction {
    func rollback()
}

public class Statement {
    private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    private var sqlite: OpaquePointer? = nil
    private var sqliteStatement: OpaquePointer? = nil
    private var resultColumns: [String: Int] = [:]
    public var uncompiledSql = ""
    
    public var query: String {
        String(cString: sqlite3_sql(self.sqliteStatement))
    }
    
    @available(iOS 10.0, *)
    public var expandedQuery: String {
        String(cString: sqlite3_expanded_sql(self.sqliteStatement))
    }
    
    @available(macOS 12.0, *)
    @available(iOS 15.0, *)
    public var normalizedQuery: String {
        String(cString: sqlite3_normalized_sql(self.sqliteStatement))
    }
    
    public var columnCount: Int {
        return Int(sqlite3_column_count(self.sqliteStatement))
    }
    
    init?(sqlite: OpaquePointer?, query: String) {
        var uncompiledSql: UnsafePointer<CChar>? = nil
        if sqlite3_prepare_v2(sqlite, query, -1, &self.sqliteStatement, &uncompiledSql) == SQLITE_OK {
            self.sqlite = sqlite
            if let uncompiledSql = uncompiledSql, strlen(uncompiledSql) > 0 {
                self.uncompiledSql = String(cString: uncompiledSql)
                print("warning: uncompiled sql - \(self.uncompiledSql)")
            }
        } else {
            return nil
        }
    }
    
    @discardableResult
    public func step() throws -> Bool {
        var result = false
        let stepResult = sqlite3_step(self.sqliteStatement)
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
    
    public func reset(includingBindings: Bool = false) throws {
        if includingBindings {
            sqlite3_clear_bindings(self.sqliteStatement)
        }
        if sqlite3_reset(self.sqliteStatement) != SQLITE_OK {
            throw sqliteError()
        }
    }
    
    public func finalize() {
        sqlite3_finalize(self.sqliteStatement)
        self.sqliteStatement = nil
    }
    
    public func bind(parameters: [Any?]) throws {
        for i in 0..<parameters.count {
            let parameter = parameters[i]
            try bindValue(parameter, forIndex: i + 1)
        }
    }
    
    public func bind(parameters: [String: Any?]) throws {
        for parameter in parameters {
            try bindValue(parameter.value, forName: parameter.key)
        }
    }
    
    public func bindInt(_ value: Int?, forIndex index: Int) throws {
        if let value = value {
            if sqlite3_bind_int64(self.sqliteStatement, Int32(index), Int64(value)) != SQLITE_OK {
                try bindFailed()
            }
        } else {
            bindNULL(forIndex: index)
        }
    }
    
    public func bindString(_ value: String?, forIndex index: Int) throws {
        if let stringValue = value {
            if sqlite3_bind_text(self.sqliteStatement, Int32(index), (stringValue as NSString).utf8String, -1, nil) != SQLITE_OK {
                try bindFailed()
            }
        } else {
            bindNULL(forIndex: index)
        }
    }
    
    public func bindDouble(_ value: Double?, forIndex index: Int) throws {
        if let value = value {
            if sqlite3_bind_double(self.sqliteStatement, Int32(index), value) != SQLITE_OK {
                try bindFailed()
            }
        } else {
            bindNULL(forIndex: index)
        }
    }
    
    public func bindBool(_ value: Bool?, forIndex index: Int) throws {
        if let value = value {
            if sqlite3_bind_int(self.sqliteStatement, Int32(index), value ? 1 : 0) != SQLITE_OK {
                try bindFailed()
            }
        } else {
            bindNULL(forIndex: index)
        }
    }
    
    public func bindData(_ value: Data?, forIndex index: Int) throws {
        if let value = value {
            let data = value as NSData
            if sqlite3_bind_blob(self.sqliteStatement, Int32(index), data.bytes, Int32(data.length), SQLITE_TRANSIENT) != SQLITE_OK {
                try bindFailed()
            }
        } else {
            bindNULL(forIndex: index)
        }
    }
    
    public func bindValue(_ value: Any?, forIndex index: Int) throws {
        switch value {
        case let stringValue as String?:
            try bindString(stringValue, forIndex: index)
        case let integerValue as Int?:
            try bindInt(integerValue, forIndex: index)
        case let doubleValue as Double?:
            try bindDouble(doubleValue, forIndex: index)
        case let boolValue as Bool?:
            try bindBool(boolValue, forIndex: index)
        case let dataValue as Data?:
            try bindData(dataValue, forIndex: index)
        default:
            bindNULL(forIndex: index)
        }
    }
    
    public func bindInt(_ value: Int?, forName name: String) throws {
        let index = getBindIndex(forName: name)
        try bindInt(value, forIndex: index)
    }
    
    public func bindString(_ value: String?, forName name: String) throws {
        let index = getBindIndex(forName: name)
        try bindString(value, forIndex: index)
    }
    
    public func bindDouble(_ value: Double?, forName name: String) throws {
        let index = getBindIndex(forName: name)
        try bindDouble(value, forIndex: index)
    }
    
    public func bindBool(_ value: Bool?, forName name: String) throws {
        let index = getBindIndex(forName: name)
        try bindBool(value, forIndex: index)
    }
    
    public func bindData(_ value: Data?, forName name: String) throws {
        let index = getBindIndex(forName: name)
        try bindData(value, forIndex: index)
    }
    
    public func bindValue(_ value: Any?, forName name: String) throws {
        let index = getBindIndex(forName: name)
        try bindValue(value, forIndex: index)
    }
    
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
    
    public func getInt(forIndex index: Int) -> Int? {
        if isColumnNULL(forIndex: index) {
            return nil
        } else {
            return Int(sqlite3_column_int64(self.sqliteStatement, Int32(index)))
        }
    }
    
    public func getString(forIndex index: Int) -> String? {
        if isColumnNULL(forIndex: index) {
            return nil
        } else {
            return String(cString: sqlite3_column_text(self.sqliteStatement, Int32(index)))
        }
    }
    
    public func getDouble(forIndex index: Int) -> Double? {
        if isColumnNULL(forIndex: index) {
            return nil
        } else {
            return sqlite3_column_double(self.sqliteStatement, Int32(index))
        }
    }
    
    public func getBool(forIndex index: Int) -> Bool? {
        if isColumnNULL(forIndex: index) {
            return nil
        } else {
            return Int(sqlite3_column_int64(self.sqliteStatement, Int32(index))) != 0
        }
    }
    
    public func getData(forIndex index: Int) -> Data? {
        if isColumnNULL(forIndex: index) {
            return nil
        } else {
            let length = sqlite3_column_bytes(self.sqliteStatement, Int32(index))
            return Data(bytes: sqlite3_column_blob(self.sqliteStatement, Int32(index)), count: Int(length))
        }
    }
    
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
    
    public func getInt(forName name: String) -> Int? {
        if let index = self.resultColumns[name] {
            return getInt(forIndex: index)
        } else {
            return nil
        }
    }
    
    public func getString(forName name: String) -> String? {
        if let index = self.resultColumns[name] {
            return getString(forIndex: index)
        } else {
            return nil
        }
    }
    
    public func getDouble(forName name: String) -> Double? {
        if let index = self.resultColumns[name] {
            return getDouble(forIndex: index)
        } else {
            return nil
        }
    }
    
    public func getBool(forName name: String) -> Bool? {
        if let index = self.resultColumns[name] {
            return getBool(forIndex: index)
        } else {
            return nil
        }
    }
    
    public func getData(forName name: String) -> Data? {
        if let index = self.resultColumns[name] {
            return getData(forIndex: index)
        } else {
            return nil
        }
    }
    
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
        let error = SQLiteError(
            code: code ?? Int(sqlite3_errcode(self.sqlite)),
            message: "\(String(cString: sqlite3_errmsg(self.sqlite)))\n\(self.query)"
        )
        #if DEBUG
        print(error)
        #endif
        return error
    }
}
