import XCTest
@testable import DersArsiviCore

/// Beyaz sayfaya çizim yapan küçük tuval.
private struct Sheet {
    let width = 480, height = 300
    var rgba: [UInt8]

    init() { rgba = [UInt8](repeating: 255, count: 480 * 300 * 4) }

    mutating func rect(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, _ c: (UInt8, UInt8, UInt8)) {
        for y in max(0, y0)..<min(height, y1) {
            for x in max(0, x0)..<min(width, x1) {
                let i = (y * width + x) * 4
                rgba[i] = c.0; rgba[i + 1] = c.1; rgba[i + 2] = c.2
            }
        }
    }

    /// Basılı satır: koyu, yoğun.
    mutating func printed(_ text: String, _ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int,
                          color: (UInt8, UInt8, UInt8) = (20, 20, 20)) -> PageAnalysis.Line {
        rect(x0, y0, x1, y1, color)
        return PageAnalysis.Line(text: text, bbox: box(x0, y0, x1, y1), confidence: 1)
    }

    /// Kalemle yazılmış satır: ince, seyrek, mor çizgiler; OCR'ın emin olmadığı.
    mutating func handwritten(_ text: String, _ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int) -> PageAnalysis.Line {
        let purple: (UInt8, UInt8, UInt8) = (120, 40, 200)
        let mid = (y0 + y1) / 2
        rect(x0, mid, x1, mid + 1, purple)
        for x in stride(from: x0, to: x1, by: 8) { rect(x, y0 + 1, x + 1, y1 - 1, purple) }
        return PageAnalysis.Line(text: text, bbox: box(x0, y0, x1, y1), confidence: 0.5)
    }

    func box(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int) -> BoundingBox {
        BoundingBox(x: Double(x0) / Double(width), y: Double(y0) / Double(height),
                    width: Double(x1 - x0) / Double(width), height: Double(y1 - y0) / Double(height))
    }
}

final class PageAnalysisTests: XCTestCase {
    func testHandwrittenLinesBecomeOneNoteAndPrintedLinesStayText() {
        var s = Sheet()
        var lines: [PageAnalysis.Line] = []
        for (i, y) in stride(from: 30, to: 150, by: 20).enumerated() {
            lines.append(s.printed("basılı \(i)", 100, y, 300, y + 10))
        }
        let blue = s.printed("Mavi başlık", 100, 10, 200, 20, color: (30, 80, 200))
        lines.append(blue)
        let a = s.handwritten("el notu bir", 100, 180, 260, 192)
        let b = s.handwritten("el notu iki", 110, 200, 280, 212)
        lines += [a, b]

        let result = PageAnalysis.analyze(rgba: s.rgba, width: s.width, height: s.height, lines: lines)
        XCTAssertEqual(result.handwriting, [lines.count - 2, lines.count - 1])
        XCTAssertEqual(result.notes.count, 1)
        let note = try! XCTUnwrap(result.notes.first)
        XCTAssertEqual(note.kind, .handwriting)
        XCTAssertEqual(note.labels.map(\.text), ["el notu bir", "el notu iki"])
        XCTAssertGreaterThan(a.bbox.fractionInside(note.bbox), 0.99)
        XCTAssertGreaterThan(b.bbox.fractionInside(note.bbox), 0.99)
        XCTAssertLessThan(note.bbox.y, a.bbox.y)
        XCTAssertFalse(result.looksComplex, "birkaç not sayfayı karışık yapmaz")
    }

    func testMostlyHandwrittenPageLooksComplex() {
        var s = Sheet()
        var lines: [PageAnalysis.Line] = [s.printed("Başlık", 100, 10, 220, 22)]
        for (i, y) in stride(from: 40, to: 260, by: 24).enumerated() {
            lines.append(s.handwritten("not \(i)", 60, y, 380, y + 14))
        }
        let result = PageAnalysis.analyze(rgba: s.rgba, width: s.width, height: s.height, lines: lines)
        XCTAssertTrue(result.looksComplex)
        XCTAssertGreaterThan(result.handwritingShare, 0.8)
    }

    func testStarNextToLineMarksIt() {
        var s = Sheet()
        let starred = s.printed("işaretli satır", 100, 50, 300, 60)
        let plain = s.printed("düz satır", 100, 100, 300, 110)
        let farAway = s.printed("uzak işaretli değil", 100, 150, 200, 160)
        s.rect(85, 50, 95, 60, (230, 30, 30))      // satırın hemen solunda kırmızı yıldız
        s.rect(400, 150, 410, 160, (230, 30, 30))  // satırdan çok uzakta
        let result = PageAnalysis.analyze(rgba: s.rgba, width: s.width, height: s.height,
                                          lines: [starred, plain, farAway])
        XCTAssertEqual(result.marked, [0])
        XCTAssertTrue(result.handwriting.isEmpty)
    }

    func testHighlighterTouchingTextAndMarksInsideFiguresAreNotMarks() {
        var s = Sheet()
        s.rect(96, 48, 304, 62, (250, 230, 60))     // fosforlu kalem satırı biraz taşırıyor
        let line = s.printed("vurgulu satır", 100, 50, 300, 60)
        s.rect(300, 120, 460, 280, (200, 210, 230))  // şekil
        s.rect(320, 200, 330, 210, (230, 30, 30))
        let label = s.printed("etiket", 340, 200, 380, 210)
        let figure = s.box(300, 120, 460, 280)
        let result = PageAnalysis.analyze(rgba: s.rgba, width: s.width, height: s.height,
                                          lines: [line, label], figures: [figure])
        XCTAssertTrue(result.marked.isEmpty)
    }
}
