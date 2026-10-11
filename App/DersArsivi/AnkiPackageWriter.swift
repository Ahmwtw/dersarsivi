import DersArsiviCore
import Foundation
import SQLite3

/// Anki paketini (.apkg) yazar: koleksiyon veritabanı (SQLite), "media" listesi ve numaralı görseller tek ZIP'te.
enum AnkiPackageWriter {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func write(_ package: AnkiPackage, imageData: (OcclusionMedia) -> Data?) throws -> Data {
        let dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("anki-\(UUID().uuidString).anki2")
        defer { try? FileManager.default.removeItem(at: dbURL) }
        try writeCollection(package, to: dbURL)

        var zip = ZipArchive()
        zip.add(path: "collection.anki2", contents: try Data(contentsOf: dbURL))
        zip.add(path: "media", contents: Data(package.mediaManifest.utf8))
        for (index, media) in package.media.enumerated() {
            guard let data = imageData(media) else { throw Failure(message: "Şekil görseli bulunamadı") }
            zip.add(path: String(index), contents: data)
        }
        return zip.finish()
    }

    private static func writeCollection(_ package: AnkiPackage, to url: URL) throws {
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK, let db else {
            throw Failure(message: "Anki veritabanı açılamadı")
        }
        defer { sqlite3_close(db) }

        func check(_ code: Int32) throws {
            guard code == SQLITE_OK || code == SQLITE_DONE else {
                throw Failure(message: "Anki veritabanı yazılamadı: \(String(cString: sqlite3_errmsg(db)))")
            }
        }
        func run(_ sql: String, _ values: [Any]) throws {
            var statement: OpaquePointer?
            try check(sqlite3_prepare_v2(db, sql, -1, &statement, nil))
            defer { sqlite3_finalize(statement) }
            for (i, value) in values.enumerated() {
                let index = Int32(i + 1)
                switch value {
                case let number as Int64:
                    try check(sqlite3_bind_int64(statement, index, number))
                case let text as String:
                    try check(sqlite3_bind_text(statement, index, text, -1, transient))
                default:
                    throw Failure(message: "Desteklenmeyen değer")
                }
            }
            try check(sqlite3_step(statement))
        }

        try check(sqlite3_exec(db, "BEGIN", nil, nil, nil))
        for sql in AnkiPackage.schema { try check(sqlite3_exec(db, sql, nil, nil, nil)) }
        let col = package.collection
        try run(AnkiPackage.insertCollection,
                [col.crt, col.mod, col.scm, col.conf, col.models, col.decks, col.dconf])
        for note in package.notes {
            try run(AnkiPackage.insertNote,
                    [note.id, note.guid, note.mid, note.mod, note.tags, note.flds, note.sfld, note.csum])
        }
        for card in package.cards {
            try run(AnkiPackage.insertCard, [card.id, card.nid, card.did, card.mod, card.due])
        }
        try check(sqlite3_exec(db, "COMMIT", nil, nil, nil))
    }

    /// SQLite metni hemen kopyalasın (Swift dizesinin ömrü bağlama çağrısıyla biter).
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}
