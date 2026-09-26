import GRDB

struct ImageProcessorModel {
    var id: String
    var type: String
    var order: Int
    var isEnabled: Bool
    var configuration: String

    static func createTable(_ db: Database) throws {
        try db.create(table: databaseTableName, ifNotExists: true) {
            $0.primaryKey("id", .text)
            $0.column("type", .text).notNull()
            $0.column("order", .integer).notNull()
            $0.column("isEnabled", .boolean).notNull()
            $0.column("configuration", .text).notNull()
        }
    }
}

extension ImageProcessorModel: TableRecord { static let databaseTableName = "imageprocessor" }

extension ImageProcessorModel: Codable, FetchableRecord, PersistableRecord {}
