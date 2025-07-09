//
//  SqliteError.swift
//  SqliteStore
//
//  Created by Aikyuichi on 10/9/19.
//  Copyright (c) 2022 aikyuichi <aikyu.sama@gmail.com>
//

import Foundation
import SQLite3

public struct SQLiteError: Error, CustomStringConvertible {
    public let code: SQLiteCode
    public let message: String
    public let description: String
    
    init(code: Int, message: String) {
        if let errorCode = SQLiteCode(rawValue: code) {
            self.code = errorCode
        } else {
            self.code = SQLiteCode.SQLITE_ERROR
        }
        self.message = message
        self.description = "[\(self.code) (\(code))] \(message)"
    }
}

public enum SQLiteCode: Int {
    case SQLITE_OK = 0
    case SQLITE_ERROR = 1
    case SQLITE_INTERNAL = 2
    case SQLITE_PERM = 3
    case SQLITE_ABORT = 4
    case SQLITE_BUSY = 5
    case SQLITE_LOCKED = 6
    case SQLITE_NOMEM = 7
    case SQLITE_READONLY = 8
    case SQLITE_INTERRUPT = 9
    case SQLITE_IOERR = 10
    case SQLITE_CORRUPT = 11
    case SQLITE_NOTFOUND = 12
    case SQLITE_FULL = 13
    case SQLITE_CANTOPEN = 14
    case SQLITE_PROTOCOL = 15
    case SQLITE_EMPTY = 16
    case SQLITE_SCHEMA = 17
    case SQLITE_TOOBIG = 18
    case SQLITE_CONSTRAINT = 19
    case SQLITE_MISMATCH = 20
    case SQLITE_MISUSE = 21
    case SQLITE_NOLFS = 22
    case SQLITE_AUTH = 23
    case SQLITE_FORMAT = 24
    case SQLITE_RANGE = 25
    case SQLITE_NOTADB = 26
    case SQLITE_NOTICE = 27
    case SQLITE_WARNING = 28
    case SQLITE_ROW = 100
    case SQLITE_DONE = 101
    case SQLITE_OK_LOAD_PERMANENTLY = 256
    case SQLITE_ERROR_MISSING_COLLSEQ = 257
    case SQLITE_BUSY_RECOVERY = 261
    case SQLITE_LOCKED_SHAREDCACHE = 262
    case SQLITE_READONLY_RECOVERY = 264
    case SQLITE_IOERR_READ = 266
    case SQLITE_CORRUPT_VTAB = 267
    case SQLITE_CANTOPEN_NOTEMPDIR = 270
    case SQLITE_CONSTRAINT_CHECK = 275
    case SQLITE_AUTH_USER = 279
    case SQLITE_NOTICE_RECOVER_WAL = 283
    case SQLITE_WARNING_AUTOINDEX = 284
    case SQLITE_ERROR_RETRY = 513
    case SQLITE_ABORT_ROLLBACK = 516
    case SQLITE_BUSY_SNAPSHOT = 517
    case SQLITE_LOCKED_VTAB = 518
    case SQLITE_READONLY_CANTLOCK = 520
    case SQLITE_IOERR_SHORT_READ = 522
    case SQLITE_CORRUPT_SEQUENCE = 523
    case SQLITE_CANTOPEN_ISDIR = 526
    case SQLITE_CONSTRAINT_COMMITHOOK = 531
    case SQLITE_NOTICE_RECOVER_ROLLBACK = 539
    case SQLITE_ERROR_SNAPSHOT = 769
    case SQLITE_BUSY_TIMEOUT = 773
    case SQLITE_READONLY_ROLLBACK = 776
    case SQLITE_IOERR_WRITE = 778
    case SQLITE_CORRUPT_INDEX = 779
    case SQLITE_CANTOPEN_FULLPATH = 782
    case SQLITE_CONSTRAINT_FOREIGNKEY = 787
    case SQLITE_READONLY_DBMOVED = 1032
    case SQLITE_IOERR_FSYNC = 1034
    case SQLITE_CANTOPEN_CONVPATH = 1038
    case SQLITE_CONSTRAINT_FUNCTION = 1043
    case SQLITE_READONLY_CANTINIT = 1288
    case SQLITE_IOERR_DIR_FSYNC = 1290
    case SQLITE_CANTOPEN_DIRTYWAL = 1294
    case SQLITE_CONSTRAINT_NOTNULL = 1299
    case SQLITE_READONLY_DIRECTORY = 1544
    case SQLITE_IOERR_TRUNCATE = 1546
    case SQLITE_CANTOPEN_SYMLINK = 1550
    case SQLITE_CONSTRAINT_PRIMARYKEY = 1555
    case SQLITE_IOERR_FSTAT = 1802
    case SQLITE_CONSTRAINT_TRIGGER = 1811
    case SQLITE_IOERR_UNLOCK = 2058
    case SQLITE_CONSTRAINT_UNIQUE = 2067
    case SQLITE_IOERR_RDLOCK = 2314
    case SQLITE_CONSTRAINT_VTAB = 2323
    case SQLITE_IOERR_DELETE = 2570
    case SQLITE_CONSTRAINT_ROWID = 2579
    case SQLITE_IOERR_BLOCKED = 2826
    case SQLITE_CONSTRAINT_PINNED = 2835
    case SQLITE_IOERR_NOMEM = 3082
    case SQLITE_CONSTRAINT_DATATYPE = 3091
    case SQLITE_IOERR_ACCESS = 3338
    case SQLITE_IOERR_CHECKRESERVEDLOCK = 3594
    case SQLITE_IOERR_LOCK = 3850
    case SQLITE_IOERR_CLOSE = 4106
    case SQLITE_IOERR_DIR_CLOSE = 4362
    case SQLITE_IOERR_SHMOPEN = 4618
    case SQLITE_IOERR_SHMSIZE = 4874
    case SQLITE_IOERR_SHMLOCK = 5130
    case SQLITE_IOERR_SHMMAP = 5386
    case SQLITE_IOERR_SEEK = 5642
    case SQLITE_IOERR_DELETE_NOENT = 5898
    case SQLITE_IOERR_MMAP = 6154
    case SQLITE_IOERR_GETTEMPPATH = 6410
    case SQLITE_IOERR_CONVPATH = 6666
    case SQLITE_IOERR_VNODE = 6922
    case SQLITE_IOERR_AUTH = 7178
    case SQLITE_IOERR_BEGIN_ATOMIC = 7434
    case SQLITE_IOERR_COMMIT_ATOMIC = 7690
    case SQLITE_IOERR_ROLLBACK_ATOMIC = 7946
    case SQLITE_IOERR_DATA = 8202
    case SQLITE_IOERR_CORRUPTFS = 8458
    
    public var description: String {
        return String(cString: sqlite3_errstr(Int32(self.rawValue)))
    }
}
