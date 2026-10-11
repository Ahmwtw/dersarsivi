import XCTest
@testable import DersArsiviCore

/// Piksel kutusundan normalleştirilmiş OCR satırı.
private func line(_ text: String, _ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double,
                  w: Double = 2000, h: Double = 1257) -> ExtractedBlock {
    ExtractedBlock(text: text, bbox: BoundingBox(x: x0 / w, y: y0 / h, width: (x1 - x0) / w, height: (y1 - y0) / h),
                   confidence: 0.9)
}

final class LayoutAnalyzerTests: XCTestCase {
    /// Gerçek bir iki sütunlu ders slaytının (Klinik Fizyoloji, üfürümler) satır kutularına göre.
    func testTwoColumnSlideIsReadColumnByColumnAndLinesBecomeParagraphs() {
        let lines = [
            line("• Tam kapanmayan kapaklar", 1090, 680, 1675, 735),
            line("Klinik Fizyoloji", 350, 20, 870, 100),
            line("• Üfürümler", 245, 140, 535, 195),
            line("• Üfürüm, kalp ve büyük", 320, 215, 830, 270),
            line("damarlardaki türbülan kan", 360, 272, 910, 325),
            line("akımının oluşturduğu sestir.", 360, 327, 930, 380),
            line("Yapısal hastalıkların yanı sıra,", 360, 382, 960, 435),
            line("artmış akım durumlarında da", 360, 437, 960, 490),
            line("duyulabilir.", 360, 492, 595, 545),
            line("• NEDENLERİ;", 245, 570, 570, 625),
            line("• Kısmi tıkanıklık (aort", 320, 645, 780, 700),
            line("stenozu)", 360, 702, 535, 755),
            line("• Akımın artması (anemi)", 320, 765, 845, 820),
            line("• Genişlemiş boşluklara kanın", 320, 830, 935, 885),
            line("fırlatılması (aort", 360, 887, 690, 940),
            line("anevrizması)", 360, 942, 620, 995),
            line("32", 980, 975, 1012, 1003),
            line("2018", 1640, 10, 1690, 25),
            line("50", 1940, 0, 1965, 12),
            line("• Üfürümler", 1015, 525, 1300, 580),
            line("• NEDENLERİ;", 1015, 605, 1340, 660),
            line("(mitral kapak regürjitasyonu)", 1125, 737, 1720, 790),
            line("• Kanın yüksek basınçlı", 1090, 800, 1580, 855),
            line("bölgeden düşük basınçlı", 1125, 857, 1625, 910),
            line("alana doğru geçişine neden", 1125, 912, 1695, 965),
            line("olan şantlar (VSD)", 1125, 967, 1495, 1020),
        ]

        let result = LayoutAnalyzer.paragraphs(from: lines, pageWidth: 2000, pageHeight: 1257).map(\.text)

        XCTAssertEqual(result, [
            "Klinik Fizyoloji",
            "• Üfürümler",
            "• Üfürüm, kalp ve büyük damarlardaki türbülan kan akımının oluşturduğu sestir. "
                + "Yapısal hastalıkların yanı sıra, artmış akım durumlarında da duyulabilir.",
            "• NEDENLERİ;",
            "• Kısmi tıkanıklık (aort stenozu)",
            "• Akımın artması (anemi)",
            "• Genişlemiş boşluklara kanın fırlatılması (aort anevrizması)",
            "2018",
            "50",
            "• Üfürümler",
            "• NEDENLERİ;",
            "• Tam kapanmayan kapaklar (mitral kapak regürjitasyonu)",
            "• Kanın yüksek basınçlı bölgeden düşük basınçlı alana doğru geçişine neden olan şantlar (VSD)",
            "32",
        ])
    }

    func testMergedParagraphKeepsLowestConfidenceAndUnionBox() {
        var a = line("Birinci satır", 100, 100, 600, 150)
        a.confidence = 0.9
        var b = line("ikinci satır", 100, 152, 500, 202)
        b.confidence = 0.4
        let result = LayoutAnalyzer.paragraphs(from: [b, a], pageWidth: 2000, pageHeight: 1257)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].text, "Birinci satır ikinci satır")
        XCTAssertEqual(result[0].confidence, 0.4)
        XCTAssertEqual(result[0].bbox!.y * 1257, 100, accuracy: 0.001)
        XCTAssertEqual((result[0].bbox!.y + result[0].bbox!.height) * 1257, 202, accuracy: 0.001)
    }

    func testHeadingNumberedItemsHyphenationAndLinesWithoutBox() {
        let lines = [
            line("Glikoliz", 100, 50, 400, 130),
            line("1) Hekzokinaz glu-", 100, 160, 600, 210),
            line("kozu fosforiller", 130, 212, 560, 262),
            line("2) Fosfofruktokinaz", 100, 280, 640, 330),
            ExtractedBlock(text: "kutusuz satır"),
        ]
        let result = LayoutAnalyzer.paragraphs(from: lines, pageWidth: 2000, pageHeight: 1257).map(\.text)
        XCTAssertEqual(result, ["Glikoliz", "1) Hekzokinaz glukozu fosforiller", "2) Fosfofruktokinaz", "kutusuz satır"])
    }
}
