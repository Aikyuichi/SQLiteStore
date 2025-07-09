# SQLiteStore
![Static Badge](https://img.shields.io/badge/swift-5-orange)
![GitHub Release](https://img.shields.io/github/v/release/Aikyuichi/SQLiteStore)
![Static Badge](https://img.shields.io/badge/platform-iOS-green)
![GitHub License](https://img.shields.io/github/license/Aikyuichi/SQLiteStore)

Use SQLite databases easily.

## Usage
```Swift
import SQLiteStore
```

```Swift
do {
    let dbPath = "/path/to/the/database/file"
    try Database.open(dbPath) { db in
        try db.executeStatement("INSERT INTO user (id, name, lastname) VALUES (@id, @name, @lastname)", parameters: [
            "@id": 1,
            "@name": "John",
            "@lastname": "Smith"
        ])
        let user = try db.selectFirst("SELECT name, lastname FROM user WHERE id = ?", parameters: [1])
    }
} catch {
    print(error)
}
```

### With prepare statements
```Swift
do {
    let dbPath = "/path/to/the/database/file"
    try Database.open(dbPath) { db in
        let query = """
        INSERT INTO user (
            id,
            name,
            lastname
        ) VALUES (
            @id,
            @name,
            @lastname
        )
        """
        try db.prepareStatement(query) { stmt in
            try stmt.bindInt(1, forName: "@id")
            try stmt.bindString("John", forName: "@name")
            try stmt.bindString("Smith", forName: "@lastname")
            try stmt.step()
        }

        var users: [User] = []
        try db.prepareStatement("SELECT id, name, lastname FROM user") { stmt in
            while try stmt.step() {
                users.append(User(
                    id: stmt.getInt(forName: "id")!,
                    name: stmt.getString(forName: "name")!,
                    lastname: stmt.getString(forName: "lastname")!
                ))
            }
        }
    }
} catch {
    print(error)
}
```

## Author

Aikyuichi, aikyu.sama@gmail.com

## License

SQLiteStore is available under the MIT license. See the LICENSE file for more info.
