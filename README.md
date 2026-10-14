# SQLiteStore

![Swift](https://img.shields.io/badge/swift-5-orange)
![GitHub Release](https://img.shields.io/github/v/release/Aikyuichi/SQLiteStore)
![Platform](https://img.shields.io/badge/platform-iOS%2012%2B-green)
![GitHub License](https://img.shields.io/github/license/Aikyuichi/SQLiteStore)

SQLiteStore is a lightweight Swift wrapper for opening SQLite databases, running parameterized statements, and reading query results. It also provides prepared statements, transactions, database registration, and schema-inspection helpers.

## Requirements

- Swift 5.10 or later
- iOS 12 or later

## Installation

In Xcode, add `https://github.com/Aikyuichi/SQLiteStore` as a Swift package dependency and add the `SQLiteStore` product to your target.

## Quick start

`Database.open(_:execute:)` opens an existing database for the duration of the closure and closes it when the closure exits. Create the database file before opening it if it does not already exist. Use bound parameters for values rather than interpolating them into SQL.

```swift
import SQLiteStore

let databasePath = "/path/to/database.sqlite"

do {
    try Database.open(databasePath) { db in
        try db.executeQuery("""
            CREATE TABLE IF NOT EXISTS users (
                id INTEGER PRIMARY KEY,
                name TEXT NOT NULL,
                lastname TEXT NOT NULL
            )
            """)

        try db.executeStatement(
            "INSERT INTO users (name, lastname) VALUES (@name, @lastname)",
            parameters: [
                "@name": "John",
                "@lastname": "Smith"
            ]
        )

        let user = try db.selectFirst(
            "SELECT id, name, lastname FROM users WHERE id = ?",
            parameters: [db.lastInsertRowId]
        )
        let name = user?["name"] as? String
        print(name ?? "User not found")
    }
} catch {
    print("Database operation failed: \(error)")
}
```

`executeQuery(_:)` is for SQL without bound values, such as schema changes. Use `executeStatement(_:parameters:)` or `select(_:parameters:)` when supplying values. Parameters can be positional (`?`) or named (`@name`).

## Querying data

`select` returns rows as dictionaries keyed by column name. Values are returned as Swift values such as `Int`, `Double`, `String`, `Data`, or `nil` for SQL `NULL`.

```swift
let users = try db.select(
    "SELECT id, name FROM users WHERE lastname = @lastname ORDER BY name",
    parameters: ["@lastname": "Smith"]
)

for user in users {
    if let name = user["name"] as? String {
        print(name)
    }
}
```

For a single scalar value, use a typed selection method such as `selectInt`, `selectString`, `selectDouble`, or `selectBool`:

```swift
let userCount = try db.selectInt("SELECT COUNT(*) FROM users") ?? 0
```

## Prepared statements

Use a prepared statement when you need typed column access or want to execute the same SQL repeatedly. Getters return optionals because a column may be `NULL` or the requested column name may not exist.

```swift
try db.prepareStatement(
    "SELECT id, name FROM users WHERE lastname = @lastname"
) { statement in
    try statement.bind(string: "Smith", forName: "@lastname")

    while try statement.step() {
        if let id = statement.getInt(forName: "id"),
           let name = statement.getString(forName: "name") {
            print("\(id): \(name)")
        }
    }
}
```

To reuse a prepared statement, bind values, call `step()`, then call `reset()` before binding the next set of values. Use `reset(includingBindings: true)` to clear existing bindings as well.

## Transactions

The transaction closure commits when it completes and rolls back if it throws:

```swift
try db.transaction {
    try db.executeStatement(
        "INSERT INTO users (name, lastname) VALUES (?, ?)",
        parameters: ["Ada", "Lovelace"]
    )
    try db.executeStatement(
        "INSERT INTO users (name, lastname) VALUES (?, ?)",
        parameters: ["Grace", "Hopper"]
    )
}
```

## Registering a database

For applications that access a database from multiple places, register it once and then open it by key. A database registered as the default can be opened without specifying its key.

```swift
Database.register(
    path: "/path/to/database.sqlite",
    forKey: "main",
    default: true
)

try Database.open { db in
    let userCount = try db.selectInt("SELECT COUNT(*) FROM users") ?? 0
    print(userCount)
}
```

`Database.register(fromMainBundleWithName:forKey:copyToDocumentDirectory:readonly:default:)` and `Database.register(fromDocumentDirectoryWithName:forKey:readonly:default:)` are also available on iOS.

## More

The `Database` API also includes database attachment, SQLite error callbacks, integrity and foreign-key checks, schema metadata, and user-version helpers. See the public API documentation in the source for details.

## License

SQLiteStore is available under the MIT license. See [LICENSE](LICENSE) for details.

## Support & Donations

If you find `SQLiteStore` helpful and would like to support its ongoing development and maintenance, consider making a donation:

- **GitHub Sponsors**: [Sponsor @Aikyuichi on GitHub](https://github.com/sponsors/Aikyuichi)
- **Starknet (USDC / ETH / STRK)**: `0x07E42a15Ad7236Ec21CeF4e7d0c353310F76d3D430Fa0E59eb29027a1F7C3A4e`

Your support is greatly appreciated! ❤️
