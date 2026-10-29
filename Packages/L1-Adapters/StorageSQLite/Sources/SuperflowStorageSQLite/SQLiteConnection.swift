import Foundation
import SQLite3

public struct SQLiteError: Error, LocalizedError, Sendable {
    public let code: Int32
    public let message: String
    public let sql: String?
    public let extendedCode: Int32
    public let systemCode: Int32

    public init(code: Int32, message: String, sql: String? = nil,
                extendedCode: Int32? = nil, systemCode: Int32 = 0) {
        self.code = code
        self.message = message
        self.sql = sql
        self.extendedCode = extendedCode ?? code
        self.systemCode = systemCode
    }

    /// SQLite reports a full volume as `SQLITE_FULL`, but a failed `-shm`
    /// allocation surfaces as `SQLITE_IOERR` with `ENOSPC` in the system code.
    public var isDiskFull: Bool {
        systemCode == Int32(ENOSPC) || systemCode == Int32(EDQUOT) || code & 0xff == SQLITE_FULL
    }

    public var errorDescription: String? {
        let detail = "SQLite \(code) (extended \(extendedCode), system \(systemCode)): \(message)"
        let context = sql.map { "\(detail) [\($0)]" } ?? detail
        if isDiskFull {
            return "Not enough disk space. Free some space and try again. \(context)"
        }
        return context
    }
}

enum SQLValue {
    case text(String)
    case integer(Int64)
    case real(Double)
    case null
    case blob(Data)
}

/// One connection. Callers serialize access through the owning actor, so the
/// wrapper stays deliberately small and synchronous.
final class SQLiteConnection {
    let handle: OpaquePointer

    init(path: String) throws {
        var pointer: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let result = sqlite3_open_v2(path, &pointer, flags, nil)
        guard result == SQLITE_OK, let pointer else {
            let message = pointer.map { String(cString: sqlite3_errmsg($0)) } ?? "could not open database"
            let extendedCode = pointer.map { sqlite3_extended_errcode($0) } ?? result
            let systemCode = pointer.map { sqlite3_system_errno($0) } ?? 0
            if let pointer { sqlite3_close_v2(pointer) }
            throw SQLiteError(code: result, message: message,
                              extendedCode: extendedCode, systemCode: systemCode)
        }
        handle = pointer
        sqlite3_busy_timeout(handle, 5_000)
        try configureForRuntime()
    }

    deinit { sqlite3_close_v2(handle) }

    func execute(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(handle, sql, nil, nil, &error)
        guard result == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(handle))
            sqlite3_free(error)
            throw SQLiteError(code: result, message: message, sql: sql,
                              extendedCode: sqlite3_extended_errcode(handle),
                              systemCode: sqlite3_system_errno(handle))
        }
    }

    func prepare(_ sql: String) throws -> SQLiteStatement {
        try SQLiteStatement(connection: self, sql: sql)
    }

    func scalarInt(_ sql: String, _ values: [SQLValue] = []) throws -> Int64 {
        let statement = try prepare(sql)
        try statement.bind(values)
        guard try statement.step() else { return 0 }
        return statement.int(0)
    }

    func scalarText(_ sql: String, _ values: [SQLValue] = []) throws -> String? {
        let statement = try prepare(sql)
        try statement.bind(values)
        guard try statement.step() else { return nil }
        return statement.text(0)
    }

    var changes: Int { Int(sqlite3_changes(handle)) }

    func transaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE")
        do {
            let value = try body()
            try execute("COMMIT")
            return value
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    var userVersion: Int32 {
        get throws { Int32(try scalarInt("PRAGMA user_version")) }
    }

    func setUserVersion(_ version: Int32) throws {
        try execute("PRAGMA user_version = \(version)")
    }

    func quickCheck() throws -> Bool {
        try scalarText("PRAGMA quick_check") == "ok"
    }

    func configureForRuntime() throws {
        try execute("PRAGMA journal_mode=WAL")
        try execute("PRAGMA synchronous=NORMAL")
        try execute("PRAGMA foreign_keys=ON")
        try execute("PRAGMA temp_store=MEMORY")
    }
}

final class SQLiteStatement {
    private let connection: SQLiteConnection
    private let handle: OpaquePointer
    private let sql: String

    init(connection: SQLiteConnection, sql: String) throws {
        self.connection = connection
        self.sql = sql
        var pointer: OpaquePointer?
        let result = sqlite3_prepare_v2(connection.handle, sql, -1, &pointer, nil)
        guard result == SQLITE_OK, let pointer else {
            throw SQLiteError(code: result, message: String(cString: sqlite3_errmsg(connection.handle)), sql: sql,
                              extendedCode: sqlite3_extended_errcode(connection.handle),
                              systemCode: sqlite3_system_errno(connection.handle))
        }
        handle = pointer
    }

    deinit { sqlite3_finalize(handle) }

    func bind(_ values: [SQLValue]) throws {
        sqlite3_reset(handle)
        sqlite3_clear_bindings(handle)
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            let result: Int32
            switch value {
            case .text(let string):
                result = string.withCString { pointer in
                    sqlite3_bind_text(handle, index, pointer, -1,
                                      unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                }
            case .integer(let int):
                result = sqlite3_bind_int64(handle, index, int)
            case .real(let double):
                result = sqlite3_bind_double(handle, index, double)
            case .null:
                result = sqlite3_bind_null(handle, index)
            case .blob(let data):
                result = data.withUnsafeBytes { raw in
                    sqlite3_bind_blob(handle, index, raw.baseAddress, Int32(raw.count),
                                      unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                }
            }
            guard result == SQLITE_OK else {
                throw SQLiteError(code: result, message: String(cString: sqlite3_errmsg(connection.handle)), sql: sql,
                                  extendedCode: sqlite3_extended_errcode(connection.handle),
                                  systemCode: sqlite3_system_errno(connection.handle))
            }
        }
    }

    @discardableResult
    func step() throws -> Bool {
        let result = sqlite3_step(handle)
        switch result {
        case SQLITE_ROW: return true
        case SQLITE_DONE: return false
        default:
            throw SQLiteError(code: result, message: String(cString: sqlite3_errmsg(connection.handle)), sql: sql,
                              extendedCode: sqlite3_extended_errcode(connection.handle),
                              systemCode: sqlite3_system_errno(connection.handle))
        }
    }

    func text(_ index: Int32) -> String? {
        guard sqlite3_column_type(handle, index) != SQLITE_NULL,
              let pointer = sqlite3_column_text(handle, index) else { return nil }
        return String(cString: pointer)
    }

    func int(_ index: Int32) -> Int64 { sqlite3_column_int64(handle, index) }
    func double(_ index: Int32) -> Double { sqlite3_column_double(handle, index) }
    func isNull(_ index: Int32) -> Bool { sqlite3_column_type(handle, index) == SQLITE_NULL }

    func data(_ index: Int32) -> Data? {
        guard sqlite3_column_type(handle, index) != SQLITE_NULL,
              let pointer = sqlite3_column_blob(handle, index) else { return nil }
        let count = Int(sqlite3_column_bytes(handle, index))
        return Data(bytes: pointer, count: count)
    }
}
