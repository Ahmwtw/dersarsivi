import Foundation

/// Anki destesi paketinin (.apkg) içeriği: koleksiyon veritabanına yazılacak satırlar ve medya listesi.
/// Veritabanını yazmak uygulamanın işidir (SQLite); burada yalnız Anki'nin beklediği değerler üretilir.
/// Biçim: eski "collection.anki2" (şema 11); AnkiMobile, AnkiDroid ve Anki masaüstü içe aktarır.
public struct AnkiPackage: Sendable {
    public struct NoteRow: Equatable, Sendable {
        public var id: Int64
        public var guid: String
        public var mid: Int64
        public var mod: Int64
        public var tags: String
        public var flds: String
        public var sfld: String
        public var csum: Int64
    }

    public struct CardRow: Equatable, Sendable {
        public var id: Int64
        public var nid: Int64
        public var did: Int64
        public var mod: Int64
        public var due: Int64
    }

    public struct Collection: Equatable, Sendable {
        public var crt: Int64
        public var mod: Int64
        public var scm: Int64
        public var conf: String
        public var models: String
        public var decks: String
        public var dconf: String
    }

    /// Not türünün sabit kimliği: yeniden içe aktarımda aynı tür kullanılır, yeni tür çoğalmaz.
    public static let modelID: Int64 = 1_728_600_000_101
    public static let modelName = "DersArşivi Görsel Kapatma"
    public static let fieldNames = ["Başlık", "Soru", "Cevap", "Etiket", "Kaynak"]

    public var collection: Collection
    public var notes: [NoteRow]
    public var cards: [CardRow]
    public var media: [OcclusionMedia]
    public let deckID: Int64

    public init(deckName: String, cards occlusion: [OcclusionCard], media: [OcclusionMedia], now: Date) {
        let ms = Int64(now.timeIntervalSince1970 * 1000)
        let seconds = ms / 1000
        let deckID = Self.deckID(for: deckName)
        self.deckID = deckID
        self.media = media
        notes = occlusion.enumerated().map { i, card in
            let fields = [card.header, card.front, card.back, card.answer, card.source]
            return NoteRow(id: ms + Int64(i), guid: card.guid, mid: Self.modelID, mod: seconds,
                           tags: " DersArşivi görsel-kapatma ", flds: fields.joined(separator: "\u{1f}"),
                           sfld: Self.stripHTML(fields[0]), csum: Self.checksum(fields[0]))
        }
        cards = notes.enumerated().map { i, note in
            CardRow(id: ms + Int64(i), nid: note.id, did: deckID, mod: seconds, due: Int64(i + 1))
        }
        collection = Collection(
            crt: seconds / 86_400 * 86_400, mod: ms, scm: ms,
            conf: Self.json(Self.conf),
            models: Self.json([String(Self.modelID): Self.model(deckID: deckID, mod: seconds)]),
            decks: Self.json(["1": Self.deck(id: 1, name: "Default", mod: seconds),
                              String(deckID): Self.deck(id: deckID, name: deckName, mod: seconds)]),
            dconf: Self.json(["1": Self.deckConf]))
    }

    /// Paketteki "media" dosyası: ZIP içindeki numaralı dosyaların Anki'deki adları.
    public var mediaManifest: String {
        Self.json(Dictionary(uniqueKeysWithValues: media.enumerated().map { (String($0.offset), $0.element.name) }))
    }

    /// Koleksiyon veritabanının tabloları (Anki şema 11).
    public static let schema = [
        """
        CREATE TABLE col (id integer primary key, crt integer not null, mod integer not null, scm integer not null,
        ver integer not null, dty integer not null, usn integer not null, ls integer not null, conf text not null,
        models text not null, decks text not null, dconf text not null, tags text not null)
        """,
        """
        CREATE TABLE notes (id integer primary key, guid text not null, mid integer not null, mod integer not null,
        usn integer not null, tags text not null, flds text not null, sfld integer not null, csum integer not null,
        flags integer not null, data text not null)
        """,
        """
        CREATE TABLE cards (id integer primary key, nid integer not null, did integer not null, ord integer not null,
        mod integer not null, usn integer not null, type integer not null, queue integer not null,
        due integer not null, ivl integer not null, factor integer not null, reps integer not null,
        lapses integer not null, left integer not null, odue integer not null, odid integer not null,
        flags integer not null, data text not null)
        """,
        """
        CREATE TABLE revlog (id integer primary key, cid integer not null, usn integer not null,
        ease integer not null, ivl integer not null, lastIvl integer not null, factor integer not null,
        time integer not null, type integer not null)
        """,
        "CREATE TABLE graves (usn integer not null, oid integer not null, type integer not null)",
        "CREATE INDEX ix_notes_usn on notes (usn)",
        "CREATE INDEX ix_cards_usn on cards (usn)",
        "CREATE INDEX ix_revlog_usn on revlog (usn)",
        "CREATE INDEX ix_cards_nid on cards (nid)",
        "CREATE INDEX ix_cards_sched on cards (did, queue, due)",
        "CREATE INDEX ix_revlog_cid on revlog (cid)",
        "CREATE INDEX ix_notes_csum on notes (csum)",
    ]

    public static let insertCollection =
        "INSERT INTO col VALUES (1, ?, ?, ?, 11, 0, 0, 0, ?, ?, ?, ?, '{}')"
    public static let insertNote = "INSERT INTO notes VALUES (?, ?, ?, ?, -1, ?, ?, ?, ?, 0, '')"
    public static let insertCard = "INSERT INTO cards VALUES (?, ?, ?, 0, ?, -1, 0, 0, ?, 0, 0, 0, 0, 0, 0, 0, 0, '')"

    // MARK: Anki değerleri

    /// Deste adından sabit kimlik: aynı klasör her dışa aktarımda aynı desteye gider.
    static func deckID(for name: String) -> Int64 {
        let hex = SHA256Hasher.hexDigest(Data(name.utf8)).prefix(12)
        return 1_500_000_000_000 + Int64(hex, radix: 16)! % 100_000_000_000
    }

    /// Anki'nin yinelenen not denetimi için: ilk alanın düz metninin SHA-1'inin ilk 8 hanesi.
    static func checksum(_ field: String) -> Int64 {
        Int64(SHA1Hasher.hexDigest(Data(stripHTML(field).utf8)).prefix(8), radix: 16)!
    }

    static func stripHTML(_ text: String) -> String {
        var out = ""
        var inTag = false
        for ch in text {
            if ch == "<" { inTag = true } else if ch == ">" { inTag = false } else if !inTag { out.append(ch) }
        }
        return out.replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&amp;", with: "&")
    }

    static func json(_ value: Any) -> String {
        let data = try! JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    static let css = """
        .card { font-family: -apple-system, "Helvetica Neue", Arial, sans-serif; font-size: 18px; text-align: center;
          color: #1c1c1e; background: #ffffff; }
        .nightMode.card, .night_mode .card { color: #f2f2f7; background: #1c1c1e; }
        .baslik { font-size: 14px; color: #8e8e93; margin-bottom: 8px; }
        .io { position: relative; display: inline-block; max-width: 100%; line-height: 0; }
        .io img { display: block; max-width: 100%; height: auto; margin: 0; }
        .io .m { position: absolute; box-sizing: border-box; background: #f6c453; border: 1px solid #b7871b;
          border-radius: 3px; }
        .io .m.q { background: #e8604c; border-color: #a63322; }
        .io .m.a { background: transparent; border: 3px solid #e8604c; }
        .etiket { font-size: 22px; font-weight: 600; margin-top: 12px; }
        .kaynak { font-size: 13px; color: #8e8e93; margin-top: 6px; }
        """

    static func model(deckID: Int64, mod: Int64) -> [String: Any] {
        [
            "id": modelID, "name": modelName, "type": 0, "mod": mod, "usn": -1, "sortf": 0, "did": deckID,
            "tags": [String](), "vers": [Int](), "css": css, "latexsvg": false,
            "latexPre": "\\documentclass[12pt]{article}\n\\special{papersize=3in,5in}\n\\usepackage{amssymb,amsmath}\n"
                + "\\pagestyle{empty}\n\\setlength{\\parindent}{0in}\n\\begin{document}\n",
            "latexPost": "\\end{document}",
            "req": [[0, "any", [1]] as [Any]],
            "flds": fieldNames.enumerated().map { i, name -> [String: Any] in
                ["name": name, "ord": i, "font": "Arial", "size": 20, "media": [String](), "rtl": false,
                 "sticky": false]
            },
            "tmpls": [[
                "name": "Görsel kapatma", "ord": 0, "did": NSNull(), "bqfmt": "", "bafmt": "",
                "qfmt": "<div class=\"baslik\">{{Başlık}}</div>\n{{Soru}}",
                "afmt": "<div class=\"baslik\">{{Başlık}}</div>\n{{Cevap}}\n<hr id=answer>\n"
                    + "<div class=\"etiket\">{{Etiket}}</div>\n<div class=\"kaynak\">{{Kaynak}}</div>",
            ] as [String: Any]],
        ]
    }

    static func deck(id: Int64, name: String, mod: Int64) -> [String: Any] {
        ["id": id, "name": name, "desc": "", "mod": mod, "usn": -1, "dyn": 0, "conf": 1, "collapsed": false,
         "extendNew": 10, "extendRev": 50, "newToday": [0, 0], "revToday": [0, 0], "lrnToday": [0, 0],
         "timeToday": [0, 0]]
    }

    static var conf: [String: Any] { [
        "activeDecks": [1], "curDeck": 1, "newSpread": 0, "collapseTime": 1200, "timeLim": 0, "estTimes": true,
        "dueCounts": true, "curModel": NSNull(), "nextPos": 1, "sortType": "noteFld", "sortBackwards": false,
        "addToCur": true,
    ] }

    static var deckConf: [String: Any] { [
        "id": 1, "name": "Default", "mod": 0, "usn": 0, "maxTaken": 60, "autoplay": true, "timer": 0,
        "replayq": true, "dyn": false,
        "new": ["delays": [1, 10], "ints": [1, 4, 7], "initialFactor": 2500, "order": 1, "perDay": 20,
                "bury": true, "separate": true] as [String: Any],
        "rev": ["perDay": 200, "ease4": 1.3, "fuzz": 0.05, "minSpace": 1, "ivlFct": 1, "maxIvl": 36500,
                "bury": true] as [String: Any],
        "lapse": ["delays": [10], "mult": 0, "minInt": 1, "leechFails": 8, "leechAction": 0] as [String: Any],
    ] }
}
