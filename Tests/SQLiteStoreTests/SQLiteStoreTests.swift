import Foundation
import Testing
@testable import SQLiteStore

private struct TestFailure: Error { }

private func makeDatabasePath() throws -> String {
    let path = FileManager.default.temporaryDirectory
        .appendingPathComponent("SQLiteStoreTests-\(UUID().uuidString).sqlite")
        .path
    guard FileManager.default.createFile(atPath: path, contents: nil) else {
        throw CocoaError(.fileWriteUnknown)
    }
    return path
}

@Test func executesAndReadsParameterizedStatements() throws {
    let path = try makeDatabasePath()
    defer { try? FileManager.default.removeItem(atPath: path) }
    let db = try Database.open(path)
    defer { db.close() }

    try db.executeQuery("""
        CREATE TABLE records (
            id INTEGER PRIMARY KEY,
            name TEXT NOT NULL,
            amount REAL NOT NULL,
            enabled INTEGER NOT NULL,
            payload BLOB,
            optional TEXT
        )
        """)
    let payload = Data([0, 1, 127, 255])
    try db.executeStatement(
        "INSERT INTO records (name, amount, enabled, payload, optional) VALUES (?, ?, ?, ?, ?)",
        parameters: ["Ada", 12.5, true, payload, nil] as [Any?]
    )

    #expect(db.lastInsertRowId == 1)
    #expect(db.affectedRows == 1)

    let selectedRecord = try db.selectFirst(
        "SELECT id, name, amount, enabled, payload, optional FROM records WHERE id = @id",
        parameters: ["@id": 1]
    )
    let record = try #require(selectedRecord)
    #expect(record["id"] as? Int == 1)
    #expect(record["name"] as? String == "Ada")
    #expect(record["amount"] as? Double == 12.5)
    #expect(record["enabled"] as? Int == 1)
    #expect(record["payload"] as? Data == payload)
    #expect(record.keys.contains("optional"))
    if let optional = record["optional"] {
        #expect(optional == nil)
    } else {
        Issue.record("The NULL column should be present in the result")
    }
}

@Test func executesBatchesAndReturnsQueryResults() throws {
    let path = try makeDatabasePath()
    defer { try? FileManager.default.removeItem(atPath: path) }
    let db = try Database.open(path)
    defer { db.close() }

    try db.executeQuery("CREATE TABLE items (id INTEGER, label TEXT)")
    let rows: [[Any?]] = [[1, "first"], [2, "second"], [3, "third"]]
    try db.executeStatement("INSERT INTO items VALUES (?, ?)", parameters: rows)

    let labels = try db.select("SELECT label FROM items ORDER BY id")
    #expect(labels.count == 3)
    #expect(labels.compactMap { $0["label"] as? String } == ["first", "second", "third"])
    #expect(try db.selectInt("SELECT COUNT(*) FROM items") == 3)
    #expect(try db.selectString("SELECT label FROM items WHERE id = ?", parameters: [2]) == "second")
    #expect(try db.selectFirst("SELECT id FROM items WHERE id = ?", parameters: [99]) == nil)
}

@Test func readsScalarValuesWithPositionalAndNamedParameters() throws {
    let path = try makeDatabasePath()
    defer { try? FileManager.default.removeItem(atPath: path) }
    let db = try Database.open(path)
    defer { db.close() }

    #expect(try db.selectBool("SELECT ? = 1", parameters: [1]) == true)
    #expect(try db.selectBool("SELECT @enabled", parameters: ["@enabled": false]) == false)
    #expect(try db.selectDouble("SELECT ? * 1.5", parameters: [4]) == 6.0)
    #expect(try db.selectInt("SELECT @value + 2", parameters: ["@value": 5]) == 7)
    #expect(try db.selectString("SELECT @value", parameters: ["@value": "named"]) == "named")
    #expect(try db.selectInt("SELECT NULL") == nil)
}

@Test func statementSupportsTypedBindingAndNamedColumnAccess() throws {
    let path = try makeDatabasePath()
    defer { try? FileManager.default.removeItem(atPath: path) }
    let db = try Database.open(path)
    defer { db.close() }

    try db.prepareStatement("SELECT @number AS number, @text AS text, @flag AS flag, @data AS data") { statement in
        try statement.bind(int: 42, forName: "@number")
        try statement.bind(string: "value", forName: "@text")
        try statement.bind(bool: true, forName: "@flag")
        try statement.bind(data: Data([4, 2]), forName: "@data")

        #expect(statement.columnCount == 4)
        #expect(statement.query.contains("SELECT"))
        let hasRow = try statement.step()
        #expect(hasRow)
        #expect(statement.getInt(forName: "number") == 42)
        #expect(statement.getString(forName: "text") == "value")
        #expect(statement.getBool(forName: "flag") == true)
        #expect(statement.getData(forName: "data") == Data([4, 2]))

        try statement.reset()
        #expect(try statement.step())
        #expect(statement.getInt(forIndex: 0) == 42)
    }
}

@Test func transactionRollsBackWhenItsBodyThrows() throws {
    let path = try makeDatabasePath()
    defer { try? FileManager.default.removeItem(atPath: path) }
    let db = try Database.open(path)
    defer { db.close() }

    try db.executeQuery("CREATE TABLE values_table (value INTEGER)")
    try db.executeQuery("INSERT INTO values_table VALUES (1)")

    do {
        try db.transaction {
            try db.executeQuery("INSERT INTO values_table VALUES (2)")
            throw TestFailure()
        }
        Issue.record("The transaction should propagate the error")
    } catch is TestFailure {
        // Expected: the transaction should roll back before propagating the error.
    }

    #expect(try db.selectInt("SELECT COUNT(*) FROM values_table") == 1)
    #expect(try db.selectInt("SELECT value FROM values_table") == 1)
}

@Test func reportsSQLiteErrorsWithTheFailingQuery() throws {
    let path = try makeDatabasePath()
    defer { try? FileManager.default.removeItem(atPath: path) }
    let db = try Database.open(path)
    defer { db.close() }

    try db.executeQuery("CREATE TABLE unique_values (value INTEGER UNIQUE)")
    try db.executeQuery("INSERT INTO unique_values VALUES (1)")
    let query = "INSERT INTO unique_values VALUES (1)"

    do {
        try db.executeQuery(query)
        Issue.record("The unique constraint should reject the duplicate value")
    } catch let error as SQLiteError {
        #expect(error.code.rawValue == SQLiteCode.SQLITE_CONSTRAINT.rawValue)
        #expect(error.query == query)
        #expect(!error.message.isEmpty)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@Test func exposesSchemaMetadataAndIntegrityChecks() throws {
    let path = try makeDatabasePath()
    defer { try? FileManager.default.removeItem(atPath: path) }
    let db = try Database.open(path)
    defer { db.close() }

    try db.executeQuery("CREATE TABLE entries (id INTEGER PRIMARY KEY, title TEXT)")
    try db.executeQuery("CREATE INDEX entries_title_idx ON entries (title)")
    db.setUserVersion(7)

    #expect(db.getUserVersion() == 7)
    #expect(db.getInfo(ofTable: "entries").contains { $0["name"] as? String == "title" })
    #expect(db.getTables().contains { $0["name"] as? String == "entries" })
    #expect(db.getIndexes(ofTable: "entries").contains { $0["name"] as? String == "entries_title_idx" })
    #expect(db.getInfo(ofIndex: "entries_title_idx").contains { $0["name"] as? String == "title" })
    #expect(db.checkIntegrity().first?.values.compactMap { $0 as? String } == ["ok"])
    #expect(db.checkIntegrity(quick: true).first?.values.compactMap { $0 as? String } == ["ok"])
    #expect(db.checkIntegrity(ofTable: "entries").first?.values.compactMap { $0 as? String } == ["ok"])
    #expect(db.checkIntegrity(ofTable: "entries", quick: true).first?.values.compactMap { $0 as? String } == ["ok"])
    #expect(db.checkForeignKeys().isEmpty)
}

@Test func updaterAppliesOnlyPendingVersionsAndReportsCallbacks() throws {
    let path = try makeDatabasePath()
    defer { try? FileManager.default.removeItem(atPath: path) }

    let entry = try UpdateEntry(
        key: "test",
        version: 1,
        json: ["commands": ["CREATE TABLE updated (value INTEGER)"]]
    )
    var beforeCount = 0
    var afterCount = 0
    let updater = DbUpdater(
        databaseFile: path,
        updates: [entry],
        beforeUpdate: { _ in beforeCount += 1 },
        afterUpdate: { _, error in
            #expect(error == nil)
            afterCount += 1
        }
    )

    updater.run()
    updater.run()

    #expect(beforeCount == 1)
    #expect(afterCount == 1)
    let db = try Database.open(path)
    defer { db.close() }
    #expect(db.getUserVersion() == 1)
    #expect(db.getTables().contains { $0["name"] as? String == "updated" })
}

@Test func updaterRollsBackAFailedVersion() throws {
    let path = try makeDatabasePath()
    defer { try? FileManager.default.removeItem(atPath: path) }

    let entry = try UpdateEntry(
        key: "test",
        version: 1,
        json: ["commands": [
            "CREATE TABLE transient (value INTEGER)",
            "THIS IS NOT VALID SQL"
        ]]
    )
    var reportedError: Error?
    let updater = DbUpdater(
        databaseFile: path,
        updates: [entry],
        beforeUpdate: nil,
        afterUpdate: { _, error in reportedError = error }
    )

    updater.run()

    #expect(reportedError != nil)
    let db = try Database.open(path)
    defer { db.close() }
    #expect(db.getUserVersion() == 0)
    #expect(!db.getTables().contains { $0["name"] as? String == "transient" })
}
