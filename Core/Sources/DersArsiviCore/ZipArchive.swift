import Foundation

/// Sıkıştırmasız (stored) ZIP yazıcı. JPEG zaten sıkıştırılmış, Markdown küçük; bağımlılık eklememek için yeterli.
/// Dosya adları UTF-8 olarak işaretlenir (Türkçe karakterler bozulmaz).
public struct ZipArchive {
    private var data = Data()
    private var central = Data()
    private var count = 0

    public init() {}

    public mutating func add(path: String, contents: Data, modified: Date = Date()) {
        let name = Data(path.utf8)
        let crc = CRC32.checksum(contents)
        let (time, date) = Self.dosDateTime(modified)
        let offset = UInt32(data.count)

        var local = Data()
        local.append(le32: 0x0403_4b50)
        local.append(le16: 20)          // gereken sürüm
        local.append(le16: 0x0800)      // bit 11: UTF-8 ad
        local.append(le16: 0)           // stored
        local.append(le16: time)
        local.append(le16: date)
        local.append(le32: crc)
        local.append(le32: UInt32(contents.count))
        local.append(le32: UInt32(contents.count))
        local.append(le16: UInt16(name.count))
        local.append(le16: 0)
        local.append(name)
        data.append(local)
        data.append(contents)

        var entry = Data()
        entry.append(le32: 0x0201_4b50)
        entry.append(le16: 20)
        entry.append(le16: 20)
        entry.append(le16: 0x0800)
        entry.append(le16: 0)
        entry.append(le16: time)
        entry.append(le16: date)
        entry.append(le32: crc)
        entry.append(le32: UInt32(contents.count))
        entry.append(le32: UInt32(contents.count))
        entry.append(le16: UInt16(name.count))
        entry.append(le16: 0)           // ek alan
        entry.append(le16: 0)           // yorum
        entry.append(le16: 0)           // disk
        entry.append(le16: 0)           // iç öznitelik
        entry.append(le32: 0)           // dış öznitelik
        entry.append(le32: offset)
        entry.append(name)
        central.append(entry)
        count += 1
    }

    public func finish() -> Data {
        var out = data
        let centralOffset = UInt32(out.count)
        out.append(central)
        out.append(le32: 0x0605_4b50)
        out.append(le16: 0)
        out.append(le16: 0)
        out.append(le16: UInt16(count))
        out.append(le16: UInt16(count))
        out.append(le32: UInt32(central.count))
        out.append(le32: centralOffset)
        out.append(le16: 0)
        return out
    }

    static func dosDateTime(_ date: Date) -> (time: UInt16, date: UInt16) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let year = max(1980, c.year ?? 1980)
        let time = UInt16((c.hour ?? 0) << 11 | (c.minute ?? 0) << 5 | (c.second ?? 0) / 2)
        let day = UInt16((year - 1980) << 9 | (c.month ?? 1) << 5 | (c.day ?? 1))
        return (time, day)
    }
}

enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data { crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
        return crc ^ 0xFFFF_FFFF
    }
}

extension Data {
    mutating func append(le16 v: UInt16) {
        append(UInt8(v & 0xFF))
        append(UInt8(v >> 8))
    }

    mutating func append(le32 v: UInt32) {
        for shift in stride(from: 0, to: 32, by: 8) { append(UInt8((v >> UInt32(shift)) & 0xFF)) }
    }
}
