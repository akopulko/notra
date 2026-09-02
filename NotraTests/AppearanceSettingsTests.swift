@testable import Notra
import Testing

/// Covers persisted-font fallback without depending on the host's installed-font catalogue.
struct AppearanceSettingsTests {
    private let choices = [
        AppearanceFontChoice(fontName: "", displayName: "System Default"),
        AppearanceFontChoice(
            fontName: "ExampleMono-Regular",
            displayName: "Example Mono",
            familyFontNames: ["ExampleMono-Bold", "ExampleMono-Italic"]
        )
    ]

    @Test func preservesAnAvailableSavedFontName() {
        #expect(
            AppearanceFont.resolvedName("ExampleMono-Regular", choices: choices) == "ExampleMono-Regular"
        )
    }

    @Test func preservesTheSystemDefaultFontName() {
        #expect(AppearanceFont.resolvedName("", choices: choices) == "")
    }

    @Test func resolvesASavedFamilyVariantToTheRegularFace() {
        #expect(AppearanceFont.resolvedName("ExampleMono-Bold", choices: choices) == "ExampleMono-Regular")
    }

    @Test func resolvesAnUnavailableSavedFontNameToSystemDefault() {
        #expect(AppearanceFont.resolvedName("RemovedFont-Regular", choices: choices) == "")
    }
}
