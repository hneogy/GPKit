# The data-age API's shape: options for review

For the owner's review (2026-11-10), on branch `v2-plans`. No code yet. The API it is about is on `v2-data-age`
(b0731aa), unreleased, so nothing here breaks a released API. Its shape was parked until 2.0 planning (ruling C,
2026-11-10). The real table waits for gpconf 0.9.0's re-measure fetch (ruling of 2026-11-07).

## What is there now

```swift
enum OrbitRegime: String, CaseIterable { case geostationary, …, undefined }    // ESA's 13 classes and UFO
extension ElementSet { var regime: OrbitRegime; func age(at: Epoch) -> Double }
enum DataAge {
    struct Sample { catalogNumber, regime, older, newer, age, positionError, radial, inTrack, crossTrack }
    static func samples(_: [ElementSet], maximumAge: Double = 30) -> (samples: [Sample], failures: Int)
    struct Percentiles { count, median, p68, p95, maximum; init?(_ values: [Double]) }
    struct Row { regime, fromAge, toAge, positionError: Percentiles; init(…) }
    static func table(_: [Sample], edges: [Double] = […]) -> [Row]
    static func estimate(for: ElementSet, at: Epoch, from: [Row]) -> Row?
}
```

The reviewer's three points left open:
- **(4)** The `(samples, failures)` tuple cannot grow, and failures are a bare count.
- **(5)** A published table cannot be rebuilt: `Percentiles` has no initialiser from its figures, and `Sample` has no
  public initialiser.
- **(6)** Adding a case to `OrbitRegime` later breaks every exhaustive `switch` (GPKit is not built with library
  evolution, so a public enum is frozen to its users). Also, ESA's word is "orbit class", and `navigationSatellites`
  is plural.

## Option A: mend in place

- A `DataAge.Measurement` struct replaces the tuple: `samples`, plus `failures: [PropagationFailure.Kind: Int]`.
- Public memberwise initialisers for `Sample` and for `Percentiles(count:median:p68:p95:maximum:)`.
- `OrbitRegime` stays an enum, renamed `OrbitClass`, with `navigationSatellite` in the singular. A new ESA class
  becomes a major-version change.

**For:** the smallest change, and the familiar `switch`. **Against:** ESA has already added a class once (HAO is in
Issue 10.0), so the enum will break users again. `estimate` stays `Row?`, with nil still standing for three cases
(review 9, documented but not typed). A table is still just `[Row]`, with nothing saying what it was measured from.

## Option B: a table type, an estimate type, an open class (recommended)

- **`OrbitClass` is a struct**, `RawRepresentable` on ESA's abbreviation ("LEO", "GTO", …), with a static constant per
  class (`.lowEarth`, …) and `.undefined`. A new ESA class is a new constant and breaks nothing. A `switch` needs a
  `default`, which is honest, since classes can be added. `init(meanMotion:eccentricity:inclination:)` stays.
- **`DataAge.Measurement`**, as in A.
- **`DataAgeTable`** (a struct, `Codable`, `Sendable`) holds `rows`, `edges` and a `Provenance`. The provenance
  says:
  - where the sets came from (free text);
  - the dates the sets span;
  - the counts by class;
  - GPKit's version and the method's name.

  `init(_ measurement:edges:provenance:)` builds one from samples, and `Decodable` rebuilds a published one. That
  answers (5) without making `Sample` public to build. `Percentiles` gets a public memberwise initialiser too.
- **`DataAgeTable.estimate(for:at:) -> DataAge.Estimate`**, an enum with one case for each nil of today:
  - `.row(Row)`;
  - `.unclassified(OrbitClass)`, for UFO or a class with no rows;
  - `.olderThanTable(age:)`;
  - `.notAfterEpoch`, for a time at or before the set's epoch.

**For:** each of (4), (5) and (6) closes, and nil stops meaning three things. A table GPKit or anyone publishes
carries what it was measured from, which is the roadmap's "measured, not quoted". `Codable` is in Swift's standard
library, so the core still needs no Foundation. **Against:** more surface (three new types), and `switch` users must
write a `default`.

## Option C: B, measured incrementally

As B, plus a `DataAgeStudy` value that takes sets as they come (`add(_: [ElementSet])`, from an `ElementSetStore`'s
history or a folder read in pieces) and yields a `Measurement` at any point. This avoids holding every set and every
sample at once, as the catalogue-scale work found worthwhile.

**For:** it fits the re-measure fetch's size and the streaming work. **Against:** state and ordering rules (a set that
arrives after a newer one), and more to test. It can be added after B without breaking it.

## Recommendation

**B**, and C later if the re-measure fetch's size calls for it, which can be measured then. Do it on `v2-data-age`
once the shape is ruled, before any table is published, so the first published table is a `DataAgeTable` with its
provenance. Nothing here is released, so none of it is a breaking change to GPKit 1.x, and it can ship in 2.0 or
earlier as additive API, on the owner's word.

## Questions

1. `OrbitClass` as a struct (B) or an enum (A)? The struct is the recommendation, because ESA has already grown the
   list once.
2. Should `Provenance` name its source as free text, or as a fixed set (a gpconf fetch, a folder)? Free text is
   proposed.
3. Should the table be published as JSON in `conformance/`, beside the method and script the roadmap asks for?
   Proposed: yes.
