import Testing
import GPKit

/// The code of the article "Migrating to GPKit 2.0" (Sources/GPKit/GPKit.docc/Articles/Migrating.md), compiled and run;
/// tools/check-article-code.sh holds the article to it.
@Suite struct MigrationTests {

    // as the article prints it
    /// What to say when an element set cannot be propagated, with every kind of failure handled. In 1.x an SGP4-XP set
    /// (ephemeris type 4) came as `.notSGP4`; in 2.0 it comes as `.sgp4XP`, and this switch needs the case.
    func explain(_ failure: PropagationFailure) -> String {
        switch failure.kind {
        case .notSGP4:
            return "This element set is for a theory other than SGP4."
        case .sgp4XP:
            return "This element set is for SGP4-XP (ephemeris type 4), which GPKit does not propagate."
        case .eccentricity, .meanMotion, .perturbedEccentricity, .semiLatusRectum:
            return "This element set's orbit cannot be propagated."
        case .decayed:
            return "The satellite has decayed."
        case .time:
            return "That time is outside what GPKit can count."
        }
    }

    /// The article's test for every set SGP4 is not for.
    func notForSGP4(_ failure: PropagationFailure) -> Bool { failure.kind == .notSGP4 || failure.kind == .sgp4XP }

    func refusal(_ change: (inout ElementSet) -> Void) throws -> PropagationFailure? {
        var set = try TLE.parse(line1: "1 25544U 98067A   98324.28472222 -.00003657  11563-4  00000+0 0    10",
                                line2: "2 25544  51.5908 168.3788 0125362  86.4185 359.7454 16.05064833    05")
        change(&set)
        do { _ = try Propagator(set); return nil } catch { return error }
    }

    @Test func anSGP4XPSetIsExplainedAsOne() throws {
        let xp = try #require(try refusal { $0.ephemerisType = 4 })
        #expect(xp.kind == .sgp4XP)
        #expect(explain(xp).contains("SGP4-XP"))
        #expect(notForSGP4(xp))
        let other = try #require(try refusal { $0.meanElementTheory = "SGP8" })
        #expect(other.kind == .notSGP4 && notForSGP4(other))
        #expect(explain(other) == "This element set is for a theory other than SGP4.")
        #expect(try refusal { _ in } == nil)
    }
}
