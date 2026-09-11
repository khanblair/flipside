import XCTest
@testable import FlipsideCore

final class IdentityKeyBuilderTests: XCTestCase {

    // 1. Document path present → Tier 1 key in the exact format above, regardless of title/profile.
    func testDocumentPathProducesTier1Key() {
        let result = IdentityKeyBuilder.key(
            bundleID: "com.apple.Preview",
            documentPath: "/Users/me/Documents/report.pdf",
            title: "report.pdf",
            chromeProfileDirectory: "Profile 2"
        )

        XCTAssertEqual(result?.key, "com.apple.Preview::doc::/Users/me/Documents/report.pdf")
        XCTAssertEqual(result?.tier, .document)
    }

    // 2. No document path, plain title, no profile directory → Tier 2 key in the plain format.
    func testPlainTitleProducesTier2Key() {
        let result = IdentityKeyBuilder.key(
            bundleID: "com.apple.Terminal",
            documentPath: nil,
            title: "bash — 80x24",
            chromeProfileDirectory: nil
        )

        XCTAssertEqual(result?.key, "com.apple.Terminal::title::bash — 80x24")
        XCTAssertEqual(result?.tier, .title)
    }

    // 3. No document path, title present, Chrome profile directory present → Tier 2 key includes
    //    "::profile::<dir>::" per the format above.
    func testChromeProfileTitleProducesProfileAwareTier2Key() {
        let result = IdentityKeyBuilder.key(
            bundleID: "com.google.Chrome",
            documentPath: nil,
            title: "GitHub",
            chromeProfileDirectory: "Profile 2"
        )

        XCTAssertEqual(result?.key, "com.google.Chrome::profile::Profile 2::title::GitHub")
        XCTAssertEqual(result?.tier, .title)
    }

    // 4. VS Code title with the unsaved-indicator has the indicator stripped before being
    //    embedded in the resulting key.
    func testVSCodeUnsavedIndicatorIsStrippedFromKey() {
        let result = IdentityKeyBuilder.key(
            bundleID: "com.microsoft.VSCode",
            documentPath: nil,
            title: "● myproject — Visual Studio Code",
            chromeProfileDirectory: nil
        )

        XCTAssertEqual(result?.key, "com.microsoft.VSCode::title::myproject — Visual Studio Code")
        XCTAssertEqual(result?.tier, .title)
    }

    // 5. Neither document path nor usable title → returns nil (Tier 3).
    func testNoDocumentPathAndNoTitleReturnsNil() {
        let result = IdentityKeyBuilder.key(
            bundleID: "com.example.SomeApp",
            documentPath: nil,
            title: nil,
            chromeProfileDirectory: nil
        )

        XCTAssertNil(result)
    }

    // 6. An empty-string title is treated the same as a nil title (falls through to Tier 3
    //    if there's also no document path).
    func testEmptyStringTitleFallsThroughToNil() {
        let result = IdentityKeyBuilder.key(
            bundleID: "com.example.SomeApp",
            documentPath: nil,
            title: "",
            chromeProfileDirectory: nil
        )

        XCTAssertNil(result)
    }

    // Additional coverage: whitespace-only titles are unusable too, not just empty strings.
    func testWhitespaceOnlyTitleFallsThroughToNil() {
        let result = IdentityKeyBuilder.key(
            bundleID: "com.example.SomeApp",
            documentPath: nil,
            title: "   ",
            chromeProfileDirectory: nil
        )

        XCTAssertNil(result)
    }

    // Additional coverage: normalizedTitle helper directly.
    func testNormalizedTitleStripsVSCodeIndicatorAndTrims() {
        let normalized = IdentityKeyBuilder.normalizedTitle("● myproject — Visual Studio Code", bundleID: "com.microsoft.VSCode")
        XCTAssertEqual(normalized, "myproject — Visual Studio Code")
    }

    func testNormalizedTitleReturnsNilForNilInput() {
        XCTAssertNil(IdentityKeyBuilder.normalizedTitle(nil, bundleID: "com.example.SomeApp"))
    }

    func testNormalizedTitleReturnsNilForWhitespaceOnlyInput() {
        XCTAssertNil(IdentityKeyBuilder.normalizedTitle("   ", bundleID: "com.example.SomeApp"))
    }
}
