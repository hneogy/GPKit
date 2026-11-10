import Testing
@testable import GPKit
import SGP4Oracle

/// `Propagator.EpochReading.vallado`: the epoch as Vallado's C++ reader makes it from a TLE, so that his published
/// verification output, `tcppver.out`, is matched to its last digits; the exact epoch stays the default.
@Suite struct ValladoEpochTests {

    /// gpconf's bar for its `sgp4-ver-positions` case: every TEME component within 2e-7 of `tcppver.out`, km and km/s.
    static let bar = 2.0e-7

    /// Set 23333 of `SGP4-VER.TLE`, as the file has it (its line 2 cut at column 69).
    static let line1 = "1 23333U 94071A   94305.49999999 -.00172956  26967-3  10000-3 0    15"
    static let line2 = "2 23333  28.7490   2.3720 9728298  30.4360   1.3500  0.07309491    70"

    /// `tcppver.out`'s rows for 23333 (Vallado's C++, WGS-72, opsmode 'i'): minutes from the epoch, then the TEME
    /// position (km) and velocity (km/s), as printed.
    static let tcppver: [[Double]] = [
        [0.00000000, -9301.24542292, 3326.10200382, 2318.36441127, -8.729303005, -0.828225037, -0.122314827],
        [120.00000000, -44672.91239680, -6213.11996581, -1738.80131727, -3.719475070, -1.336673022, -0.621888261],
        [240.00000000, -67053.08885388, -14994.69685946, -5897.99072793, -2.860576613, -1.183771565, -0.568473909],
        [360.00000000, -85227.84253168, -22897.08484471, -9722.59184564, -2.426469823, -1.078592475, -0.525341431],
        [480.00000000, -100986.00419136, -30171.19698695, -13283.77044765, -2.147108978, -1.000530827, -0.491587582],
        [600.00000000, -115093.00686387, -36962.56316477, -16634.15682929, -1.945446188, -0.938947736, -0.464199202],
        [720.00000000, -127965.80064891, -43363.32967165, -19809.90480432, -1.789652016, -0.888278463, -0.441254468],
        [840.00000000, -139863.28332207, -49436.45704153, -22836.80438139, -1.663762568, -0.845315913, -0.421548627],
        [960.00000000, -150960.22978259, -55227.45413896, -25734.01408879, -1.558730986, -0.808061065, -0.404293846],
        [1080.00000000, -161381.71414630, -60770.64040903, -28516.26290017, -1.468977174, -0.775190459, -0.388951810],
        [1200.00000000, -171221.18736947, -66092.76474442, -31195.19847387, -1.390837596, -0.745785633, -0.375140398],
        [1320.00000000, -180550.82888746, -71215.23290630, -33780.24938270, -1.321788672, -0.719184752, -0.362579495],
        [1440.00000000, -189427.87533074, -76155.54943344, -36279.19882816, -1.260024473, -0.694896053, -0.351058133],
        [1560.00000000, -197898.69401409, -80928.29015181, -38698.57972447, -1.204211888, -0.672544709, -0.340413731],
        [1600.00000000, -200638.82986236, -82484.14969882, -39488.34331447, -1.186748462, -0.665472422, -0.337037582],
    ]

    /// The largest component difference from `tcppver.out`'s rows, position and velocity apart.
    static func worst(_ propagator: Propagator) throws -> (position: Double, velocity: Double) {
        var position = 0.0, velocity = 0.0
        for row in tcppver {
            let s = try propagator.state(minutesFromEpoch: row[0])
            for (mine, theirs) in zip([s.position.x, s.position.y, s.position.z], row[1...3]) { position = max(position, abs(mine - theirs)) }
            for (mine, theirs) in zip([s.velocity.x, s.velocity.y, s.velocity.z], row[4...6]) { velocity = max(velocity, abs(mine - theirs)) }
        }
        return (position, velocity)
    }

    @Test func set23333MeetsGpconfsBarWithValladosEpochAndNotWithTheExactOne() throws {
        let set = try TLE.parse(line1: Self.line1, line2: Self.line2, checksum: .ignore)
        let vallado = try Self.worst(Propagator(set, epochReading: .vallado))
        #expect(vallado.position <= Self.bar, "\(vallado.position) km")
        #expect(vallado.velocity <= Self.bar, "\(vallado.velocity) km/s")
        // the known-bad case: the exact epoch, 19 microseconds off his, is millimetres out on this orbit
        let exact = try Self.worst(Propagator(set))
        #expect(exact.position > Self.bar, "\(exact.position) km")
        #expect(try Self.worst(Propagator(set, epochReading: .exact)).position == exact.position)
        print("23333 against tcppver.out: Vallado's epoch \(vallado.position) km, \(vallado.velocity) km/s; the exact epoch \(exact.position) km")
    }

    @Test func set23333sEpochIsHisToTheBit() throws {
        let set = try TLE.parse(line1: Self.line1, line2: Self.line2, checksum: .ignore)
        // (2449657.5 + 0.49999999) - 2433281.5, as the C++ adds them
        #expect(set.epoch.valladoDaysSince1950.bitPattern == ((2_449_657.5 + 0.49999999) - 2_433_281.5).bitPattern)
        #expect(set.epoch.valladoDaysSince1950 != set.epoch.daysSince1950)
    }

    /// On every verification set, the epoch is the C++ reader's own to the bit, and the run from it is the C++'s to a
    /// micrometre (the port's own agreement on the same doubles).
    @Test func everyVerificationSetsEpochIsTheCReadersToTheBit() throws {
        var differs = 0
        for c in try VerificationCase.all() {
            var e = sgp4oracle_elements()
            var times = [0.0, 0.0, 0.0]
            let set = try TLE.parse(line1: c.line1, line2: c.line2, checksum: .ignore)
            let oracle = try #require(sgp4oracle_twoline(c.line1, c.line2WithTimes, 1, SGP4Tests.improved, SGP4Tests.wgs72, &e, &times))
            defer { sgp4oracle_free(oracle) }
            #expect(set.epoch.valladoDaysSince1950.bitPattern == e.epoch.bitPattern,
                    "\(c.catalogField): \(set.epoch.valladoDaysSince1950) against the C++'s \(e.epoch)")
            if set.epoch.daysSince1950 != e.epoch { differs += 1 }
            let run = SGP4Tests.run(try Propagator(set, epochReading: .vallado).core, against: oracle, times: times)
            #expect(run.errorsDiffer == 0, "\(c.catalogField)")
            #expect(run.maxPosition <= SGP4Tests.micrometre, "\(c.catalogField): \(run.maxPosition * 1.0e6) mm")
        }
        // the mode is not the exact epoch under another name: most of the 33 epochs part from the exact ones
        #expect(differs > 0)
        print("Vallado's epoch: all 33 verification epochs the C++ reader's to the bit; \(differs) of them not the exact epoch")
    }

    @Test func anEpochATLECannotCarryIsRoundedAsATLEWritesIt() throws {
        // a second's millionth past a hundred-millionth of a day: the TLE writer's rounding first, then his arithmetic
        let fine = try Epoch(year: 2026, month: 9, day: 21, hour: 12, minute: 0, second: 0, attosecond: 1_000_000_000_000)
        let written = try Epoch(year: 2026, month: 9, day: 21, hour: 12, minute: 0, second: 0)
        #expect(fine.valladoDaysSince1950 == written.valladoDaysSince1950)
        // the last instant of a year rounds into the next, as the writer carries it
        let late = try Epoch(year: 2025, month: 12, day: 31, hour: 23, minute: 59, second: 59, attosecond: 999_999_000_000_000_000)
        #expect(late.valladoDaysSince1950 == (try Epoch(year: 2026, month: 1, day: 1, hour: 0, minute: 0, second: 0)).valladoDaysSince1950)
        // and in a leap year, after February: 2024 day 61 is 1 March
        let march = try Epoch(year: 2024, month: 3, day: 1, hour: 6, minute: 0, second: 0)
        #expect(abs(march.valladoDaysSince1950 - march.daysSince1950) * 86_400 < 25e-6)
    }
}
