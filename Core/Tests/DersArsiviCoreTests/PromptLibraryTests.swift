import Foundation
import XCTest
@testable import DersArsiviCore

final class PromptLibraryTests: XCTestCase {
    func testIDsAreUniqueAndFieldsNonEmpty() {
        let ids = PromptLibrary.all.map(\.id)
        XCTAssertGreaterThanOrEqual(ids.count, 16)
        XCTAssertEqual(Set(ids).count, ids.count)
        for template in PromptLibrary.all {
            XCTAssertFalse(template.id.isEmpty)
            XCTAssertTrue(template.id.allSatisfy { $0.isASCII }, template.id)
            XCTAssertFalse(template.title.isEmpty, template.id)
            XCTAssertFalse(template.summary.isEmpty, template.id)
            XCTAssertFalse(template.symbol.isEmpty, template.id)
            XCTAssertFalse(template.outputHint.isEmpty, template.id)
            XCTAssertFalse(template.body.isEmpty, template.id)
        }
    }

    func testLookupByID() {
        XCTAssertEqual(PromptLibrary.template(id: "anki-tsv")?.category, .anki)
        XCTAssertEqual(PromptLibrary.template(id: "soru-temize")?.recommendsImages, true)
        XCTAssertNil(PromptLibrary.template(id: "yok"))
        for template in PromptLibrary.all {
            XCTAssertEqual(PromptLibrary.template(id: template.id), template)
        }
    }

    func testEveryCategoryHasTemplatesInDisplayOrder() {
        let categories = PromptLibrary.all.map(\.category)
        for category in PromptTemplate.Category.allCases {
            XCTAssertTrue(categories.contains(category), category.rawValue)
            XCTAssertFalse(category.title.isEmpty)
        }
        // Kategoriler arayüz sırasında gruplu: çalışma, Anki, sorular, kontrol.
        let order = PromptTemplate.Category.allCases
        let positions = categories.compactMap { order.firstIndex(of: $0) }
        XCTAssertEqual(positions, positions.sorted())
    }

    func testAnkiHeadersUseDeckNameAndRealTabs() throws {
        let context = PromptContext(deckName: "DersArşivi::Fizyoloji", sourceCount: 2)
        let tsv = try XCTUnwrap(PromptLibrary.template(id: "anki-tsv")).instructions(context)
        XCTAssertTrue(tsv.contains(
            "#separator:tab\n#html:true\n#deck:DersArşivi::Fizyoloji\n#columns:Front\tBack\tTags\tSource\tPriority\n"))
        XCTAssertTrue(tsv.contains("DersArşivi::Fizyoloji::Kalp_Fizyolojisi"))

        let cloze = try XCTUnwrap(PromptLibrary.template(id: "anki-cloze")).instructions(context)
        XCTAssertTrue(cloze.contains(
            "#separator:tab\n#html:true\n#notetype:Cloze\n#deck:DersArşivi::Fizyoloji\n#columns:Text\tBack Extra\tTags\n"))
        XCTAssertTrue(cloze.contains("{{c1::"))

        let gorsel = try XCTUnwrap(PromptLibrary.template(id: "anki-gorsel")).instructions(context)
        XCTAssertTrue(gorsel.contains("#columns:Front\tBack\tTags\tSource\tPriority"))
        XCTAssertTrue(gorsel.contains("<img src="))
    }

    func testPlaceholdersFilledAndSharedRulesAppended() {
        let context = PromptContext(deckName: "Deste", sourceCount: 7)
        for template in PromptLibrary.all {
            let text = template.instructions(context)
            XCTAssertFalse(text.contains("{DESTE}"), template.id)
            XCTAssertFalse(text.contains("{KAYNAK_SAYISI}"), template.id)
            XCTAssertTrue(text.hasSuffix("\n\n### Genel kurallar\n" + PromptLibrary.sharedRules), template.id)
        }
        let quiz = PromptLibrary.template(id: "quiz")?.instructions(context) ?? ""
        XCTAssertTrue(quiz.contains("Ekteki 7 kaynaktan"))
        XCTAssertTrue(PromptLibrary.sharedRules.contains("kaynakta net değil"))
    }

    func testImageNoteOnlyWhenImagesIncluded() {
        for template in PromptLibrary.all {
            let without = template.instructions(PromptContext(includesImages: false))
            let withImages = template.instructions(PromptContext(includesImages: true))
            XCTAssertFalse(without.contains(PromptLibrary.imageNote), template.id)
            XCTAssertTrue(withImages.hasSuffix("\n\n" + PromptLibrary.imageNote), template.id)
            XCTAssertTrue(withImages.contains("### Genel kurallar\n" + PromptLibrary.sharedRules), template.id)
        }
    }
}
