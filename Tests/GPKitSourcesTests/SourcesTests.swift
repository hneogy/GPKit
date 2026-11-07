import Foundation
import Testing
import GPKit
@testable import GPKitSources

/// GPKitSources against recorded answers only: no test makes a request.
///
/// SatNOGS DB's answer is the one request made for these tests (Resources/satnogs/, its record beside it, CC BY-SA 4.0,
/// see NOTICE). CelesTrak's answers are made up for the tests from public data: the Space Station's first element set,
/// as GPKit's own tests have it, and CelesTrak's own words for no data, which GPKit already reads. No CelesTrak capture
/// is published here.
@Suite struct SourcesTests {

    static let iss = """
    ISS (ZARYA)
    1 25544U 98067A   98324.28472222 -.00003657  11563-4  00000+0 0    10
    2 25544  51.5908 168.3788 0125362  86.4185 359.7454 16.05064833    05

    """

    static func at(_ text: String) -> Date {
        Date(timeIntervalSince1970: try! Epoch(ccsds: text).unixTime)
    }

    static func client(_ answers: [URL: HTTPAnswer], ledger: Ledger = Ledger()) -> (SourceClient, RecordedTransport) {
        let transport = RecordedTransport(answers)
        return (SourceClient(transport: transport, application: "GPKitSourcesTests/1 (+https://github.com/hneogy/GPKit)", ledger: ledger), transport)
    }

    // MARK: - CelesTrak

    @Test func theQueriesAreCelesTraksOwn() throws {
        #expect(CelesTrak.url(.catalogNumber(25544), format: .tle)?.absoluteString == "https://celestrak.org/NORAD/elements/gp.php?CATNR=25544&FORMAT=TLE")
        #expect(CelesTrak.url(.group("amateur"))?.absoluteString == "https://celestrak.org/NORAD/elements/gp.php?GROUP=amateur&FORMAT=CSV")
        #expect(CelesTrak.url(.internationalDesignator("1998-067"), format: .json)?.absoluteString == "https://celestrak.org/NORAD/elements/gp.php?INTDES=1998-067&FORMAT=JSON")
        #expect(CelesTrak.url(.name("ISS (ZARYA)"), format: .kvn)?.absoluteString == "https://celestrak.org/NORAD/elements/gp.php?NAME=ISS%20(ZARYA)&FORMAT=KVN")
        // nothing a query cannot carry as it is
        #expect(CelesTrak.url(.group("")) == nil && CelesTrak.url(.name("a&FORMAT=TLE")) == nil && CelesTrak.url(.catalogNumber(-1)) == nil)
        #expect(CelesTrak.url(.group("x"))?.host == "celestrak.org" && CelesTrak.url(.group("x"))?.scheme == "https")
    }

    @Test func anAnswerIsReadAndTheAddressIsNotAskedAgainForTwoHours() async throws {
        let url = try #require(CelesTrak.url(.catalogNumber(25544), format: .tle))
        let (client, transport) = SourcesTests.client([url: HTTPAnswer(status: 200, body: Data(SourcesTests.iss.utf8))])
        let now = SourcesTests.at("2026-11-07T12:00:00")
        guard case .fetched(let file, let attempt) = await CelesTrak.fetch(.catalogNumber(25544), format: .tle, with: client, now: now) else {
            Issue.record("not fetched"); return
        }
        #expect(file.elementSets.map(\.catalogNumber) == [25544] && attempt.status == 200 && attempt.bytes == SourcesTests.iss.utf8.count)
        // the request: once, with the program's name and GPKitSources' after it, in English
        #expect(transport.requests.count == 1)
        let headers = transport.requests[0].headers
        #expect(headers["User-Agent"] == "GPKitSourcesTests/1 (+https://github.com/hneogy/GPKit) GPKitSources (+https://github.com/hneogy/GPKit)")
        #expect(headers["Accept-Language"] == "en" && headers["Accept"] == "*/*")
        // within the two hours: the kept answer, and nothing asked
        guard case .cached(let again, _) = await CelesTrak.fetch(.catalogNumber(25544), format: .tle, with: client, now: now.addingTimeInterval(7199)) else {
            Issue.record("not cached"); return
        }
        #expect(again == file && transport.requests.count == 1)
        // after them: asked again
        guard case .fetched = await CelesTrak.fetch(.catalogNumber(25544), format: .tle, with: client, now: now.addingTimeInterval(7200)) else {
            Issue.record("not asked after two hours"); return
        }
        #expect(transport.requests.count == 2)
    }

    @Test func noDataIsAResultAndATLEAbove99999IsNotAsked() async throws {
        let url = try #require(CelesTrak.url(.catalogNumber(99_999_999)))
        let (client, transport) = SourcesTests.client([url: HTTPAnswer(status: 200, body: Data("No GP data found".utf8))])
        guard case .fetched(let file, _) = await CelesTrak.fetch(.catalogNumber(99_999_999), with: client, now: Date()) else {
            Issue.record("not fetched"); return
        }
        #expect(file.elementSets.isEmpty && file.providerMessage == "No GP data found")
        guard case .notAsked(let why) = await CelesTrak.fetch(.catalogNumber(100_000), format: .tle, with: client, now: Date()) else {
            Issue.record("asked for a TLE above 99999"); return
        }
        #expect(why.contains("99999") && transport.requests.count == 1)
    }

    @Test func anAnswerThatIsNotA200StopsEveryRequestToTheHostForTwoHours() async throws {
        let group = try #require(CelesTrak.url(.group("active")))
        let other = try #require(CelesTrak.url(.catalogNumber(25544), format: .tle))
        let (client, transport) = SourcesTests.client([
            group: HTTPAnswer(status: 403, body: Data("made up for the test: a 403 for a second download within an update".utf8)),
            other: HTTPAnswer(status: 200, body: Data(SourcesTests.iss.utf8)),
        ])
        let now = SourcesTests.at("2026-11-07T12:00:00")
        guard case .stopped(let attempt, let excerpt) = await CelesTrak.fetch(.group("active"), with: client, now: now) else {
            Issue.record("not stopped"); return
        }
        #expect(attempt.status == 403 && excerpt.hasPrefix("made up for the test"))
        // another address on the same host: held too, and nothing asked
        guard case .tooSoon(let holding) = await CelesTrak.fetch(.catalogNumber(25544), format: .tle, with: client, now: now.addingTimeInterval(60)) else {
            Issue.record("asked the host again"); return
        }
        #expect(holding.status == 403 && transport.requests.count == 1)
        guard case .fetched = await CelesTrak.fetch(.catalogNumber(25544), format: .tle, with: client, now: now.addingTimeInterval(7200)) else {
            Issue.record("still held after two hours"); return
        }
    }

    @Test func noAnswerCountsAndAPageIsUnreadable() async throws {
        let url = try #require(CelesTrak.url(.group("stations")))
        // no recorded answer: the transport throws, as one with no answer from the network does
        let (client, transport) = SourcesTests.client([:])
        let now = SourcesTests.at("2026-11-07T12:00:00")
        guard case .noAnswer(let attempt, _) = await CelesTrak.fetch(.group("stations"), with: client, now: now) else {
            Issue.record("not noAnswer"); return
        }
        #expect(attempt.status == nil)
        guard case .tooSoon = await CelesTrak.fetch(.group("stations"), with: client, now: now.addingTimeInterval(10)) else {
            Issue.record("asked again after no answer"); return
        }
        #expect(transport.requests.count == 1)

        let (pages, _) = SourcesTests.client([url: HTTPAnswer(status: 200, body: Data("<html><body>Not what was asked</body></html>".utf8))])
        guard case .unreadable(_, let reason, let excerpt) = await CelesTrak.fetch(.group("stations"), with: pages, now: now) else {
            Issue.record("a page was read"); return
        }
        #expect(!reason.isEmpty && excerpt.hasPrefix("<html>"))
    }

    @Test func theRulesHoldFromOneRunToTheNextAndAClockSetBack() async throws {
        let url = try #require(CelesTrak.url(.catalogNumber(25544), format: .tle))
        let first = Ledger()
        let (client, _) = SourcesTests.client([url: HTTPAnswer(status: 200, body: Data(SourcesTests.iss.utf8))], ledger: first)
        let now = SourcesTests.at("2026-11-07T12:00:00")
        _ = await CelesTrak.fetch(.catalogNumber(25544), format: .tle, with: client, now: now)
        // the state saved and read back, as a program does between runs
        let saved = try JSONEncoder().encode(await first.state)
        let second = Ledger(state: try JSONDecoder().decode(Ledger.State.self, from: saved))
        let (later, transport) = SourcesTests.client([url: HTTPAnswer(status: 200, body: Data(SourcesTests.iss.utf8))], ledger: second)
        guard case .tooSoon = await CelesTrak.fetch(.catalogNumber(25544), format: .tle, with: later, now: now.addingTimeInterval(3600)) else {
            Issue.record("the saved rules did not hold"); return
        }
        // a clock set back a day: the attempt holds from now for two hours, not for a day and two hours
        #expect(await second.holding(url, at: now.addingTimeInterval(-86_400)) != nil)
        #expect(await second.holding(url, at: now.addingTimeInterval(-86_400 + 7200)) == nil)
        #expect(transport.requests.isEmpty)
    }

    @Test func theCacheKeepsAnswersInAFolder() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("gpkitsources-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        await AnswerCache(folder: folder).keep(Data("kept".utf8), for: "https://celestrak.org/a?b=c")
        #expect(await AnswerCache(folder: folder).answer(for: "https://celestrak.org/a?b=c") == Data("kept".utf8))
        #expect(await AnswerCache(folder: folder).answer(for: "https://celestrak.org/other") == nil)
    }

    /// GP Passes' CelesTrak captures, which are private, read through the same code. Run where GPKIT_PRIVATE_CAPTURES
    /// names their folder; elsewhere nothing is read, and the test says so.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["GPKIT_PRIVATE_CAPTURES"] != nil, "GPKIT_PRIVATE_CAPTURES is not set"))
    func privateCapturesReadThroughTheClient() async throws {
        let folder = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["GPKIT_PRIVATE_CAPTURES"]))
        let files = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasSuffix(".csv") }.sorted()
        #expect(!files.isEmpty)
        var sets = 0
        for name in files {
            let query = CelesTrak.Query.name("CAPTURE-" + String(name.dropLast(4)).replacingOccurrences(of: "_", with: "-"))
            let url = try #require(CelesTrak.url(query))
            let (client, _) = SourcesTests.client([url: HTTPAnswer(status: 200, body: try Data(contentsOf: folder.appendingPathComponent(name)))])
            guard case .fetched(let file, _) = await CelesTrak.fetch(query, with: client, now: Date()) else {
                Issue.record("\(name): not read"); continue
            }
            print("private capture \(name): \(file.elementSets.count) element sets, \(file.refusals.count) refused\(file.providerMessage.map { ", the provider says \($0)" } ?? "")")
            sets += file.elementSets.count
        }
        print("private captures: \(files.count) files, \(sets) element sets")
    }

    // MARK: - SatNOGS DB

    static func recorded() throws -> Data {
        let url = try #require(Bundle.module.url(forResource: "transmitters-active-2026-11-07", withExtension: "json", subdirectory: "Resources/satnogs"))
        return try Data(contentsOf: url)
    }

    @Test func theRecordedTransmittersRead() throws {
        let transmitters = try SatNOGS.transmitters(from: try SourcesTests.recorded())
        #expect(transmitters.count == 2958)
        #expect(Set(transmitters.compactMap(\.satelliteID)).count == 1660)
        #expect(transmitters.allSatisfy { $0.status == "active" })
        let iss = transmitters.of(catalogNumber: 25544)
        #expect(iss.count == 41)
        let aprs = try #require(iss.first { $0.description == "Mode V APRS" })
        #expect(aprs.kind == "Transceiver" && aprs.downlinkLow == 145_825_000 && aprs.uplinkLow == 145_825_000)
        #expect(aprs.mode == "AFSK" && aprs.baud == 1200 && !aprs.inverting && !aprs.unconfirmed)
        #expect(throws: SatNOGS.Unreadable.self) { _ = try SatNOGS.transmitters(from: Data("<html></html>".utf8)) }
    }

    @Test func aTransmitterIsTunedWithGPKitsDoppler() throws {
        let transmitters = try SatNOGS.transmitters(from: try SourcesTests.recorded())
        let aprs = try #require(transmitters.of(catalogNumber: 25544).first { $0.description == "Mode V APRS" })
        let set = try ElementSets.read(SourcesTests.iss, as: .tle).elementSets[0]
        let look = try Propagator(set).look(from: Observer(latitude: 40, longitude: -75), at: try Epoch(ccsds: "1998-11-20T14:09:00"))
        #expect(aprs.downlink(at: look) == look.received(from: 145_825_000))
        #expect(aprs.uplink(at: look) == look.transmit(toBeReceivedAt: 145_825_000))
        // approaching or drawing away, the shift is a few kilohertz on two metres
        let shift = try #require(aprs.downlink(at: look)) - 145_825_000
        #expect(abs(shift) > 100 && abs(shift) < 4000, "\(shift)")
        #expect(transmitters.first { $0.downlinkLow == nil }?.downlink(at: look) == nil)
    }

    @Test func anInvertingTransponderMirrorsItsPassband() throws {
        let transmitters = try SatNOGS.transmitters(from: try SourcesTests.recorded())
        // AO-7's Mode B: 432.125 to 432.175 MHz up, 145.925 to 145.975 MHz down, inverting
        let modeB = try #require(transmitters.of(catalogNumber: 7530).first { $0.description == "Mode U/V (B) Lin" })
        #expect(modeB.inverting && modeB.kind == "Transponder")
        #expect(modeB.downlink(forUplink: 432_125_000) == 145_975_000)
        #expect(modeB.downlink(forUplink: 432_150_000) == 145_950_000)
        #expect(modeB.downlink(forUplink: 432_175_000) == 145_925_000)
        #expect(modeB.downlink(forUplink: 432_200_000) == nil)
        // a transponder that does not invert keeps the order
        let straight = try #require(transmitters.first { $0.kind == "Transponder" && !$0.inverting && $0.uplinkHigh != nil && $0.downlinkHigh != nil && $0.uplinkHigh! > $0.uplinkLow! && $0.downlinkHigh! > $0.downlinkLow! })
        let low = Double(try #require(straight.uplinkLow))
        #expect(straight.downlink(forUplink: low + 1000) == Double(try #require(straight.downlinkLow)) + 1000)
    }

    @Test func theTransmittersAreFetchedUnderTheSameRules() async throws {
        let (client, transport) = SourcesTests.client([SatNOGS.activeTransmitters: HTTPAnswer(status: 200, body: try SourcesTests.recorded())])
        let now = SourcesTests.at("2026-11-07T14:17:04")
        guard case .fetched(let transmitters, _) = await SatNOGS.fetchActiveTransmitters(with: client, now: now) else {
            Issue.record("not fetched"); return
        }
        #expect(transmitters.count == 2958 && transport.requests[0].headers["Accept"] == "application/json")
        guard case .cached = await SatNOGS.fetchActiveTransmitters(with: client, now: now.addingTimeInterval(60)) else {
            Issue.record("asked again within two hours"); return
        }
        #expect(transport.requests.count == 1)
        #expect(SatNOGS.credit.contains("CC BY-SA 4.0") && SatNOGS.credit.contains("Libre Space Foundation"))
    }
}
