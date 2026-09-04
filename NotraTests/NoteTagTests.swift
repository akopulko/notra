import Foundation
@testable import Notra
import Testing

/// Verifies the inspector accepts its optional hashtag prefix without weakening tag validation.
struct NoteTagTests {
    @Test func inspectorInputAcceptsPlainAndPrefixedTags() throws {
        let plainTag = try #require(NoteTag(inspectorInput: "Swift"))
        let prefixedTag = try #require(NoteTag(inspectorInput: "#Swift"))

        #expect(plainTag.name == "Swift")
        #expect(prefixedTag.name == "Swift")
    }

    @Test func inspectorInputRejectsInvalidPrefixedTags() {
        #expect(NoteTag(inspectorInput: "##Swift") == nil)
        #expect(NoteTag(inspectorInput: "#Swift UI") == nil)
    }
}
