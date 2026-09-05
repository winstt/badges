import XCTest

/// Priority resolution is the heart of the "which badge wins" behaviour, so it's the
/// thing worth locking down with tests. These compile against the Shared engine
/// directly (same module), so no import of the app is needed.
final class BadgeResolverTests: XCTestCase {

    private func rule(_ name: String, _ exts: [String], enabled: Bool = true) -> BadgeRule {
        BadgeRule(name: name, fileExtensions: exts, badgeAsset: name.lowercased(), isEnabled: enabled)
    }
    private func url(_ name: String) -> URL { URL(fileURLWithPath: "/tmp/\(name)") }

    // MARK: Priority (list order = priority, index 0 wins)

    func testFirstMatchingRuleWinsByOrder() {
        let a = rule("A", ["psd"]); let b = rule("B", ["psd"])
        let r = BadgeResolver(rules: [a, b])
        XCTAssertEqual(r.finderSyncBadge(for: url("x.psd"))?.id, a.id,
                       "The higher (index 0) matching rule must win.")
    }

    func testReorderChangesWinner() {
        let a = rule("A", ["psd"]); let b = rule("B", ["psd"])
        // Same rules, opposite order → the other one wins.
        XCTAssertEqual(BadgeResolver(rules: [b, a]).finderSyncBadge(for: url("x.psd"))?.id, b.id)
        XCTAssertEqual(BadgeResolver(rules: [a, b]).finderSyncBadge(for: url("x.psd"))?.id, a.id)
    }

    func testHigherDisabledRuleFallsThroughToLower() {
        let a = rule("A", ["psd"], enabled: false)   // top but off
        let b = rule("B", ["psd"])                    // lower but on
        let r = BadgeResolver(rules: [a, b])
        XCTAssertEqual(r.finderSyncBadge(for: url("x.psd"))?.id, b.id)
    }

    func testSpecificOverGeneralWhenOrderedThatWay() {
        let specific = rule("Sketch", ["sketch"])
        let general = rule("Any", ["sketch", "psd", "ai"])  // overlaps on .sketch
        let r = BadgeResolver(rules: [specific, general])
        XCTAssertEqual(r.finderSyncBadge(for: url("logo.sketch"))?.id, specific.id)
        // A non-overlapping extension still resolves to the general rule.
        XCTAssertEqual(r.finderSyncBadge(for: url("logo.ai"))?.id, general.id)
    }

    // MARK: Master switch & matching

    func testMasterOffYieldsNoBadge() {
        let r = BadgeResolver(rules: [rule("A", ["psd"])], badgingEnabled: false)
        XCTAssertNil(r.finderSyncBadge(for: url("x.psd")))
        XCTAssertTrue(r.badges(for: url("x.psd")).isEmpty)
    }

    func testNoMatchYieldsNil() {
        let r = BadgeResolver(rules: [rule("A", ["psd"])])
        XCTAssertNil(r.finderSyncBadge(for: url("x.png")))
    }

    func testExtensionMatchingIsCaseInsensitive() {
        let r = BadgeResolver(rules: [rule("A", ["psd"])])
        XCTAssertNotNil(r.finderSyncBadge(for: url("X.PSD")))
    }

    func testRuleWithMultipleExtensions() {
        let r = BadgeResolver(rules: [rule("Photoshop", ["psd", "psb"])])
        XCTAssertNotNil(r.finderSyncBadge(for: url("a.psd")))
        XCTAssertNotNil(r.finderSyncBadge(for: url("b.psb")))
        XCTAssertNil(r.finderSyncBadge(for: url("c.pdf")))
    }

    func testDisabledRuleDoesNotMatch() {
        let r = BadgeResolver(rules: [rule("A", ["psd"], enabled: false)])
        XCTAssertNil(r.finderSyncBadge(for: url("x.psd")))
    }

    func testExtensionsAreLowercasedOnInit() {
        // BadgeRule normalises extensions to lower-case at init.
        XCTAssertEqual(rule("A", ["PSD", "Psb"]).fileExtensions, ["psd", "psb"])
    }
}
