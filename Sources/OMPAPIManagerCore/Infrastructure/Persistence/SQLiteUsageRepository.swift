import CSQLite
import Foundation

public actor SQLiteUsageRepository: UsageRecording {
    private let handle: DatabaseHandle

    public init(databaseURL: URL) throws {
        var handle: OpaquePointer?
        let result = sqlite3_open_v2(databaseURL.path, &handle, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil)
        guard result == SQLITE_OK, let handle else { throw AppError.databaseError }
        self.handle = DatabaseHandle(pointer: handle)
        try Self.execute(handle, sql: """
        CREATE TABLE IF NOT EXISTS usage_records (
          id TEXT PRIMARY KEY NOT NULL,
          provider_id TEXT NOT NULL,
          model_id TEXT,
          occurred_at REAL NOT NULL,
          latency_ms INTEGER NOT NULL,
          status_code INTEGER,
          input_tokens INTEGER,
          output_tokens INTEGER,
          total_tokens INTEGER,
          source TEXT,
          error_category TEXT
        );
        CREATE INDEX IF NOT EXISTS usage_records_occurred_at ON usage_records(occurred_at DESC);
        """)
    }

    public static func applicationSupportDefault() throws -> SQLiteUsageRepository {
        guard let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw AppError.databaseError
        }
        let folder = directory.appending(path: "OMP API Manager", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return try SQLiteUsageRepository(databaseURL: folder.appending(path: "usage.sqlite"))
    }

    public func record(_ usage: GatewayUsageRecord) throws {
        let sql = """
        INSERT INTO usage_records (id, provider_id, model_id, occurred_at, latency_ms, status_code, input_tokens, output_tokens, total_tokens, source, error_category)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle.pointer, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw AppError.databaseError }
        defer { sqlite3_finalize(statement) }
        bind(usage.id.uuidString, to: statement, index: 1)
        bind(usage.providerID, to: statement, index: 2)
        bind(usage.modelID, to: statement, index: 3)
        sqlite3_bind_double(statement, 4, usage.occurredAt.timeIntervalSince1970)
        sqlite3_bind_int64(statement, 5, sqlite3_int64(usage.latencyMilliseconds))
        bind(usage.statusCode, to: statement, index: 6)
        bind(usage.inputTokens, to: statement, index: 7)
        bind(usage.outputTokens, to: statement, index: 8)
        bind(usage.totalTokens, to: statement, index: 9)
        bind(usage.source?.rawValue, to: statement, index: 10)
        bind(usage.errorCategory, to: statement, index: 11)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw AppError.databaseError }
    }

    public func recentUsage(limit: Int) throws -> [GatewayUsageRecord] {
        let sql = "SELECT id, provider_id, model_id, occurred_at, latency_ms, status_code, input_tokens, output_tokens, total_tokens, source, error_category FROM usage_records ORDER BY occurred_at DESC LIMIT ?"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle.pointer, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw AppError.databaseError }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int(statement, 1, Int32(max(1, limit)))
        var records: [GatewayUsageRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let idText = string(statement, index: 0), let id = UUID(uuidString: idText), let providerID = string(statement, index: 1) else { throw AppError.databaseError }
            let source = string(statement, index: 9).flatMap(UsageRecord.Source.init(rawValue:))
            records.append(GatewayUsageRecord(
                id: id,
                providerID: providerID,
                modelID: string(statement, index: 2),
                occurredAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 3)),
                latencyMilliseconds: Int(sqlite3_column_int64(statement, 4)),
                statusCode: optionalInteger(statement, index: 5),
                inputTokens: optionalInteger(statement, index: 6),
                outputTokens: optionalInteger(statement, index: 7),
                totalTokens: optionalInteger(statement, index: 8),
                source: source,
                errorCategory: string(statement, index: 10)
            ))
        }
        return records
    }

    public func summary(since: Date) throws -> UsageSummary {
        let sql = """
        SELECT COUNT(*), COALESCE(SUM(input_tokens), 0), COALESCE(SUM(output_tokens), 0), COALESCE(SUM(total_tokens), 0),
               COALESCE(SUM(CASE WHEN error_category IS NOT NULL THEN 1 ELSE 0 END), 0), COALESCE(AVG(latency_ms), 0)
        FROM usage_records WHERE occurred_at >= ?
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle.pointer, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw AppError.databaseError }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_double(statement, 1, since.timeIntervalSince1970)
        guard sqlite3_step(statement) == SQLITE_ROW else { throw AppError.databaseError }
        return UsageSummary(
            requestCount: Int(sqlite3_column_int64(statement, 0)),
            inputTokens: Int(sqlite3_column_int64(statement, 1)),
            outputTokens: Int(sqlite3_column_int64(statement, 2)),
            totalTokens: Int(sqlite3_column_int64(statement, 3)),
            errorCount: Int(sqlite3_column_int64(statement, 4)),
            averageLatencyMilliseconds: Int(sqlite3_column_double(statement, 5))
        )
    }

    private static func execute(_ database: OpaquePointer, sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw AppError.databaseError }
    }

    private func bind(_ string: String?, to statement: OpaquePointer, index: Int32) {
        guard let string else { sqlite3_bind_null(statement, index); return }
        sqlite3_bind_text(statement, index, string, -1, sqliteTransient)
    }

    private func bind(_ integer: Int?, to statement: OpaquePointer, index: Int32) {
        guard let integer else { sqlite3_bind_null(statement, index); return }
        sqlite3_bind_int64(statement, index, sqlite3_int64(integer))
    }

    private func string(_ statement: OpaquePointer, index: Int32) -> String? {
        guard let pointer = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: pointer)
    }

    private func optionalInteger(_ statement: OpaquePointer, index: Int32) -> Int? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return Int(sqlite3_column_int64(statement, index))
    }
}

private final class DatabaseHandle: @unchecked Sendable {
    let pointer: OpaquePointer
    init(pointer: OpaquePointer) { self.pointer = pointer }
    deinit { sqlite3_close(pointer) }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
