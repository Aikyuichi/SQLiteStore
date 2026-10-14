# Changelog

Notable changes to SQLiteStore are documented here.

## 1.0.0

- Document the public Swift APIs.

## 0.9.10

- Support applying updates to a specific database file or registered database key, using a selected updates source.
- Improve update execution and SQLite error reporting.

## 0.9.9

- Add configurable SQLite error handlers for database operations.
- Improve update completion callbacks to provide the underlying error.

## 0.9.8

- Add JSON-driven database updates, including ordered versions, SQL commands, attachment handling, and optional vacuum/optimization.
- Add callbacks before and after updates.

## 0.9.7

- Introduce `DbStore` for registering and managing database assets and connections.
- Add `DbStoreError` and throwing database access and selection APIs.

## 0.9.6

- Add database metadata and integrity utilities, including foreign-key checks, integrity checks, optimization, and schema inspection.
- Expose SQLite version, affected-row count, and last inserted row ID.
- Add expanded SQL access for prepared statements.

## 0.9.5

- Add explicit transaction lifecycle methods and throwing transaction closures.
- Improve query result handling and database update execution.

## 0.9.4

- Add transaction execution and database update support.
- Add typed scalar and first-row selection methods with positional and named parameters.

## 0.9.3

- Add database registration from file paths, the main bundle, and the Documents directory.
- Support read-only databases and attached databases.

## 0.9.2

- Add first-row and typed scalar selection methods.
- Expand prepared-statement binding and column-reading APIs.

## 0.9.1

- Add row selection and result fetching for database queries.
- Improve prepared-statement reset and binding behavior.

## 0.9.0

- Initial release with SQLite database access, prepared statements, value binding, and query execution.
