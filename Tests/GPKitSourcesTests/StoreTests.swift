import Foundation
import Testing
import GPKit
@testable import GPKitSources

/// The element-set store, the folder source and the next time a request is allowed, against the recorded fixtures in
/// Resources/fixtures (made up from the Space Station's 1998 set; its README says how). No test makes a request.
@Suite struct StoreTests {

    static func fixtures() throws -> URL {
        try #require(Bundle.module.url(forResource: "fixtures", withExtension: nil, subdirectory: "Resources"))
    }

    /// A folder holding copies of the named fixtures, for a test to read some of them; removed by the caller.
    static func folder(_ names: [String]) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("gpkitsources-store-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for name in names {
            try FileManager.default.copyItem(at: try fixtures().appendingPathComponent(name), to: folder.appendingPathComponent(name))
        }
        return folder
    }

    static func read(_ name: String) throws -> ElementSetFile {
        let format = try #require(FolderSource.format(of: name))
        return try ElementSets.read(try Data(contentsOf: try fixtures().appendingPathComponent(name)), as: format)
    }

    static func epochs(_ sets: [ElementSet]) -> [String] {
        sets.map { String($0.epoch.description.prefix(10)) }
    }

    // MARK: - The store

    @Test func eachSetIsMergedByItsEpochAndTheMergeSaysWhatItDid() async throws {
        let store = ElementSetStore()
        var report = await store.merge(try Self.read("a-2026-11-07T1200-iss.tle"))
        #expect(report.added == 1 && report.replaced == 0)
        report = await store.merge(try Self.read("b-2026-11-07T1400-iss.tle"))
        #expect(report.replaced == 1 && report.added == 0)
        report = await store.merge(try Self.read("c-2026-11-07T1600-iss-older.tle"))
        #expect(report.older == 1 && report.replaced == 0)
        // the newest is the current set, whatever order the answers came in
        #expect(await store.current(25544)?.epoch.dayOfYear == 325)
        #expect(Self.epochs(await store.history(25544)) == ["1998-11-21", "1998-11-20", "1998-11-19"])
        // the same set again changes nothing
        report = await store.merge(try Self.read("a-2026-11-07T1200-iss.tle"))
        #expect(report.unchanged == 1 && report.added + report.replaced + report.older == 0)
        #expect(await store.history(25544).count == 3)
    }

    @Test func anotherSetAtAHeldEpochIsAConflictAndTheHeldOneIsKept() async throws {
        let store = ElementSetStore()
        await store.merge(try Self.read("a-2026-11-07T1200-iss.tle"))
        let held = try #require(await store.current(25544))
        let report = await store.merge(try Self.read("d-2026-11-07T1800-iss-conflict.tle"))
        #expect(report.conflicting == [25544] && report.unchanged == 0)
        let current = await store.current(25544), count = await store.history(25544).count
        #expect(current == held && count == 1)
        #expect(held.meanAnomaly.description != (try Self.read("d-2026-11-07T1800-iss-conflict.tle")).elementSets[0].meanAnomaly.description)
    }

    @Test func theHistoryKeepsTheNewestSetsUpToItsSize() async throws {
        let two = ElementSetStore(keep: 2)
        for name in ["c-2026-11-07T1600-iss-older.tle", "a-2026-11-07T1200-iss.tle", "b-2026-11-07T1400-iss.tle"] {
            await two.merge(try Self.read(name))
        }
        #expect(Self.epochs(await two.history(25544)) == ["1998-11-21", "1998-11-20"])
        // an older set than any kept, with no room: counted, and not kept
        let report = await two.merge(try Self.read("c-2026-11-07T1600-iss-older.tle"))
        let count = await two.history(25544).count
        #expect(report.older == 1 && count == 2)
        // a size below one is one
        #expect(ElementSetStore(keep: 0).keep == 1)
    }

    @Test func refusalsAndSetsWithNoCatalogNumberAreCountedAndNotHeld() async throws {
        let store = ElementSetStore()
        let report = await store.merge(try Self.read("e-2026-11-07T2000-bad-checksum.tle"))
        #expect(report.refused == 1 && report.added == 0)
        let uncatalogued = try ElementSet(catalogNumber: nil, epoch: Epoch(ccsds: "2026-11-07T00:00:00"), meanMotion: ExactDecimal(15),
                                          eccentricity: ExactDecimal("0.0001")!, inclination: ExactDecimal(53), rightAscension: .zero,
                                          argumentOfPericenter: .zero, meanAnomaly: .zero)
        // a set built in code with no catalog number
        let built = await store.merge([uncatalogued])
        let held = await store.catalogNumbers
        #expect(built.uncatalogued == 1 && held.isEmpty)
    }

    @Test func theStaleObjectsAreTheOnesWhoseNewestSetIsOlderThanAsked() async throws {
        let store = ElementSetStore()
        await store.merge(try Self.read("a-2026-11-07T1200-iss.tle"))
        await store.merge(try Self.read("f-2026-11-07T2200-group.csv"))
        let now = try Epoch(ccsds: "2026-11-08T12:00:00")
        #expect(await store.stale(at: now, olderThan: 2) == [25544])
        #expect(await store.stale(at: now, olderThan: 1) == [25544, 270001])
        #expect(await store.stale(at: try Epoch(ccsds: "1998-11-22T07:00:00"), olderThan: 1).isEmpty)
    }

    @Test func whatIsSavedReadsBackAsTheSameSets() async throws {
        let store = ElementSetStore()
        for name in ["a-2026-11-07T1200-iss.tle", "b-2026-11-07T1400-iss.tle", "c-2026-11-07T1600-iss-older.tle", "f-2026-11-07T2200-group.csv"] {
            await store.merge(try Self.read(name))
        }
        let saved = await store.save()
        let again = try ElementSetStore(saved: saved)
        #expect(await again.catalogNumbers == [25544, 270001])
        for number in [25544, 270001] {
            let before = await store.history(number), after = await again.history(number)
            #expect(before.count == after.count)
            for (a, b) in zip(before, after) {
                var a = a, b = b
                #expect(b.source == .json)
                a.source = nil
                b.source = nil
                #expect(a == b, "\(number) at \(a.epoch)")
            }
        }
        // and saved again, the same text
        #expect(await again.save() == saved)
        // a saved text that is not a store's is refused
        #expect(throws: Refusal.self) { try ElementSetStore(saved: Data("[{\"OBJECT_NAME\":\"X\"}]".utf8)) }
    }

    // MARK: - The folder source

    @Test func theFolderIsReadByExtensionInNameOrder() async throws {
        let reading = try FolderSource(folder: try Self.fixtures()).read()
        #expect(reading.files.map(\.name) == ["a-2026-11-07T1200-iss.tle", "b-2026-11-07T1400-iss.tle", "c-2026-11-07T1600-iss-older.tle",
                                              "d-2026-11-07T1800-iss-conflict.tle", "e-2026-11-07T2000-bad-checksum.tle",
                                              "f-2026-11-07T2200-group.csv", "g-2026-11-08T0000-no-data.json"])
        #expect(reading.skipped == [".hidden.tle", "README.md", "h-notes.html"])
        #expect(reading.failed.map(\.name) == ["i-broken.xml"])
        // CelesTrak's words for no data read as a file with none
        let noData = try #require(reading.files.first { $0.name.hasPrefix("g-") }).file
        #expect(noData.elementSets.isEmpty && noData.providerMessage == "No GP data found")
        #expect(FolderSource.format(of: "x.TXT") == .tle && FolderSource.format(of: "x") == nil && FolderSource.format(of: ".kvn") == nil)
    }

    @Test func theFolderLoadsIntoTheStoreAndASecondLoadChangesNothing() async throws {
        let store = ElementSetStore()
        let (first, _) = try await FolderSource(folder: try Self.fixtures()).load(into: store)
        #expect(first.added == 2 && first.replaced == 2 && first.older == 1 && first.unchanged == 0)
        #expect(first.conflicting == [25544] && first.refused == 1 && first.uncatalogued == 0)
        #expect(Self.epochs(await store.history(25544)) == ["1998-11-22", "1998-11-21", "1998-11-20", "1998-11-19"])
        #expect(await store.current(270001)?.objectName == "GPKIT TEST OBJECT")
        let (second, _) = try await FolderSource(folder: try Self.fixtures()).load(into: store)
        #expect(second.unchanged == 5 && second.added + second.replaced + second.older == 0 && second.conflicting == [25544])
    }

    @Test func aFolderThatCannotBeListedThrows() throws {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("gpkitsources-missing-\(UUID().uuidString)")
        #expect(throws: (any Error).self) { try FolderSource(folder: missing).read() }
        // and an empty one reads as nothing
        let empty = try Self.folder([])
        defer { try? FileManager.default.removeItem(at: empty) }
        let reading = try FolderSource(folder: empty).read()
        #expect(reading.files.isEmpty && reading.failed.isEmpty && reading.skipped.isEmpty)
    }

    // MARK: - The next time the rules allow

    @Test func theNextAskIsTheEndOfTheLatestQuietTimeThatHoldsIt() async throws {
        let iss = try #require(CelesTrak.url(.catalogNumber(25544), format: .tle))
        let group = try #require(CelesTrak.url(.group("active")))
        let t0 = SourcesTests.at("2026-11-07T12:00:00")
        let ledger = Ledger()
        #expect(await ledger.nextAsk(iss, at: t0) == nil)
        // the group refused at t0 holds the whole host until t0 + 2 h
        await ledger.record(Attempt(url: group.absoluteString, askedAt: t0, status: 403), host: group.host)
        #expect(await ledger.nextAsk(iss, at: t0.addingTimeInterval(60)) == t0.addingTimeInterval(7200))
        // the Station's own address answered at t0 + 1 h (as a program might, from another host's view of it): held to t0 + 3 h
        await ledger.record(Attempt(url: iss.absoluteString, askedAt: t0.addingTimeInterval(3600), status: 200), host: iss.host)
        #expect(await ledger.nextAsk(iss, at: t0.addingTimeInterval(3700)) == t0.addingTimeInterval(10_800))
        #expect(await ledger.nextAsk(group, at: t0.addingTimeInterval(3700)) == t0.addingTimeInterval(7200))
        #expect(await ledger.nextAsk(iss, at: t0.addingTimeInterval(10_800)) == nil)
        // it agrees with fetch: tooSoon before it, asked at it
        let (client, transport) = SourcesTests.client([iss: HTTPAnswer(status: 200, body: Data(SourcesTests.iss.utf8))])
        _ = await CelesTrak.fetch(.catalogNumber(25544), format: .tle, with: client, now: t0)
        let next = try #require(await client.ledger.nextAsk(iss, at: t0.addingTimeInterval(1)))
        // the same rules with no kept answer, so that a held request is tooSoon and not cached
        let bare = SourceClient(transport: transport, application: client.application, ledger: client.ledger, cache: AnswerCache())
        guard case .tooSoon = await CelesTrak.fetch(.catalogNumber(25544), format: .tle, with: bare, now: next.addingTimeInterval(-1)) else {
            Issue.record("asked before the next ask"); return
        }
        guard case .fetched = await CelesTrak.fetch(.catalogNumber(25544), format: .tle, with: bare, now: next) else {
            Issue.record("not asked at the next ask"); return
        }
        #expect(transport.requests.count == 2)
    }
}
