# GPKit

GPKit reads GP data — OMM and TLE, including six-digit catalog numbers — and passes gpconf.

It is a Swift package with no dependencies, for macOS and iOS. The library is plain Swift and does not import
Foundation, so it builds with the Command Line Tools alone. CI is set to build and test it on macOS and on Linux.

**Status: readers, a TLE writer, SGP4 and pass prediction with Doppler.** Nothing is released. The interface for
reading is settled; the one for propagation and passes is a proposal and may still change.

## Reading

```swift
import GPKit

// what the provider served: Data, [UInt8], any collection of bytes, or a String
let file = try ElementSets.read(bytes, as: .json)      // .csv, .json, .xml, .kvn or .tle

for set in file.elementSets {
    set.catalogNumber        // 25544: an Int, whatever its width
    set.objectID             // "1998-067A", or nil when the source has none
    set.epoch                // 1998-11-20T06:49:59.999808, kept as integers
    set.meanMotion           // 16.05064833, the digits the source wrote
    set.meanMotion.double    // the nearest Double, for computing
}

for refusal in file.refusals {
    print(refusal)           // NORAD_CAT_ID "A0000" is not an integer of up to nine digits (record 2 of the file)
    refusal.kind             // .catalogNumber
    refusal.field            // "NORAD_CAT_ID"
    refusal.text             // "A0000"
}
```

One record type, `ElementSet`, whichever format the data came in. Its properties are the OMM's keywords in the OMM's
units; a TLE is read into the same record.

- **Catalog numbers are integers.** Five, six or nine digits, `catalogNumber` is an `Int` from 0 to 999,999,999. A
  TLE's Alpha-5 field is decoded on the way in, as Space-Track defines it (`A` to `Z` for 10 to 33, never `I` or
  `O`), and is not kept. No number is ever routed through five characters.
- **Values are kept as written.** A number is an `ExactDecimal`: the source's digits, not a `Double`. `.15975118E-3`
  from a CSV, `0.00015975118` from JSON and ` 15975-3` from a TLE's column are read without passing through binary,
  and equal values compare equal. `double` gives the nearest `Double`.
- **The epoch is integers.** A calendar date, a time of day, and the fraction of the second as a whole number of
  attoseconds. A TLE's eight-decimal day is an exact number of microseconds and arrives as that. Both CCSDS forms
  are read, with or without a fraction, with or without `Z`; second 60 is kept.
- **Both derivatives of the mean motion are kept**, as the TLE prints them, and the mean motion is the one the source
  wrote.

## Refusing

GPKit drops nothing without a word and guesses nothing. A record it cannot read as it stands comes back as a
`Refusal` in the record's place, with what was wrong, the field, the text that was there, and where in the file. One
bad record costs one record: the ones around it are read.

`ElementSets.read` itself throws only when the input as a whole cannot be taken for what it is said to be: bytes that
are not UTF-8, an empty input, JSON or XML that does not parse, a file that ends inside a record. A file cut short is
refused whole, so that part of a catalog is never loaded as if it were all of it.

For a TLE that means: both lines 69 printable ASCII characters, both checksums right, the two catalog fields the
same, every separator column a space, and every field what its columns are for. A letter in a numeric field, a short
line, a line 1 with no line 2 and a line that belongs to no set are each refused with that reason.

The checksum is verified by default. `ElementSets.read(bytes, as: .tle, checksum: .ignore)`, and the same argument
on `TLE.parse`, reads lines whose checksum digit is wrong or blank, for a source known to write them so. Every
other check is still made. Without the checksum a line that was altered gives no sign of it: a digit changed
elsewhere in the line is read as the value it now spells.

A provider's own answer for "no data", CelesTrak's `No GP data found`, is not an error and not a refusal: the file
has no entries, and `providerMessage` holds the answer.

## What GPKit fills in, and what it lets pass

Documented here because each is a decision made for the reader.

| | |
|---|---|
| `CENTER_NAME`, `REF_FRAME`, `TIME_SYSTEM`, `MEAN_ELEMENT_THEORY` absent, as in CelesTrak's CSV and JSON and in every TLE | `EARTH`, `TEME`, `UTC`, `SGP4`, and `ElementSet.defaulted` names each keyword that was filled in |
| `MEAN_ELEMENT_THEORY` | kept as written; `SGP4` and `SGP/SGP4` are both SGP4 (`isSGP4`) |
| `OBJECT_ID` or `OBJECT_NAME` empty, null or absent | nil. Nothing is put in its place |
| `NORAD_CAT_ID`, `EPHEMERIS_TYPE`, `CLASSIFICATION_TYPE`, `ELEMENT_SET_NO`, `REV_AT_EPOCH` absent from an OMM, which the standard allows | nil |
| a TLE's blank ephemeris type column | 0 |
| keywords and columns GPKit has no property for | kept as text in `otherKeywords` |
| a UTF-8 byte-order mark; LF or CRLF line endings | passed over |
| KVN: blank lines, `COMMENT` lines, spaces and tabs around `=`, a unit in brackets after a number, a plus sign on an integer | passed over |
| JSON: a number written as a string; one object in place of an array | read |
| XML: a namespace prefix on an element name; CDATA; the five named entities and numeric references | read. A document type declaration is refused |
| a name line beginning `0 `, as in a three-line element set | the name without the `0 ` |

Reading checks the form of a record, not its physics: an eccentricity of 2 is a number and is read.

## Writing a TLE

```swift
let lines = try TLE.write(set)
lines.line1        // "1 A0000U ...": five digits below 100000, Alpha-5 from 100000 to 339999
lines.text         // the two lines, or three with the name
```

Every value is brought to its field's resolution in decimal, exactly, a half rounding up; `TLE.write(set,
eccentricity: .truncated)` cuts the eccentricity off instead, as CelesTrak's own lines do. What a TLE cannot carry
is refused, never approximated: a catalog number that is missing, negative or above 339999, an epoch outside 1957
to 2056, a value wider than its columns. A missing classification is written `U`, and a missing ephemeris type,
element set number or revolution number as 0.

## gpconf

[gpconf](https://github.com/hneogy/gp-omm-conformance) is a conformance corpus for GP data, built from what providers
serve. GPKit's adapter for its runner is in this package (`Sources/gpconf-adapter`), and CI runs it on every push.

With gpconf 0.6.1, on 2026-10-06: **17 of 18 cases pass, each on every item exactly, and none fails or is
skipped.** The eighteenth, `satcat-70000-cutoff`, checks data and runs no parser; it reports not exercised for every
library. The run's summary is in [`conformance/`](conformance/).

```bash
swift build
gpconf run --cmd "'$PWD/.build/debug/gpkit-gpconf' parse {fmt}" --vectors-cmd "'$PWD/.build/debug/gpkit-gpconf' vectors" --write-cmd "'$PWD/.build/debug/gpkit-gpconf' write" --json gpconf-report.json
```

```bash
python3 tools/check_gpconf.py gpconf-report.json --gate
```

Thirteen of the cases read provider files, which the corpus fetches once to your machine and does not ship. CI
never fetches: it runs the five cases that need no provider file, and `tools/check_gpconf.py` without `--gate` is
its bar. The full run is made before a release, from a copy of the corpus that holds its files.

## Propagating

```swift
let propagator = try Propagator(set)                        // refuses an element set that is not for SGP4

let state = try propagator.state(at: time)                  // time is an Epoch, UTC
state.position                                              // kilometres, TEME
state.velocity                                              // kilometres per second

try propagator.state(minutesFromEpoch: 90)                  // or by minutes from the element set's epoch
```

`Propagator` is SGP4: a port to Swift of the propagation routines of David Vallado's `SGP4.cpp`, as CelesTrak
publishes it. It is a value. Making one does the initialisation, and every call after that is independent of the
calls before it, so one can be shared between tasks. A time it cannot be propagated to, a decayed satellite's for
one, is a `PropagationFailure` saying which of SGP4's conditions stopped it.

An `Epoch` is UTC. `Epoch(unixTime:)` and `unixTime` go to and from Foundation's `Date.timeIntervalSince1970`,
and `advanced(by:)` and `seconds(since:)` move and measure in seconds.

## Passes and Doppler

```swift
let home = Observer(latitude: 40.0, longitude: -75.0, height: 100)       // degrees, degrees, metres

for pass in try propagator.passes(over: home, from: now, for: 86_400) {   // the next day, above the horizon
    pass.rise?.time                     // nil when the satellite was already up at the start
    pass.culmination.look.elevation     // degrees, at its highest
    pass.set?.look.azimuth              // degrees clockwise from north; nil when still up at the end
}

let look = try propagator.look(from: home, at: now)
look.azimuth; look.elevation            // where to point
look.range                              // kilometres
look.rangeRate                          // kilometres per second, positive while it draws away
look.received(from: 437_000_000)        // what to tune a receiver to, for a downlink on 437 MHz
look.transmit(toBeReceivedAt: 145_900_000)   // what to tune a transmitter to, for an uplink on 145.9 MHz
```

`passes(over:from:for:above:)` takes a minimum elevation, the horizon by default. The elevation is sampled every 30
seconds, each crossing is narrowed to a millisecond, and a peak between two samples is looked into, so a pass
shorter than the step is found too.

What it does not do, each a choice that can be changed:

- **No refraction.** Angles are geometric. Near the horizon a satellite is heard a little before the elevation
  here reaches zero.
- **UT1 is taken to be UTC**, which it is to within 0.9 s, and the motion of the pole is left out. Together they
  move a place on the ground by under half a kilometre, which is hundredths of a degree for a low satellite.
- **One culmination a pass.** In a long pass of a high, eccentric orbit the elevation can peak twice; the highest
  peak is given. For a pass cut off by the start or the end of the search, the culmination is the highest point
  inside the search.
- **A search stops at a failure.** If the element set cannot be propagated to some time in the span, the call
  throws and gives no passes.

## How SGP4 and the passes are checked

**Against the C++ it is ported from.** The tests compile Vallado's `SGP4.cpp`, unmodified, and run it and the port
through the 33 verification element sets published with "Revisiting Spacetrack Report #3", at every time of every
case: 2,349 steps, near-Earth and deep-space orbits, the half-day and one-day resonances, and the runs that end in
each error. Given the same inputs, the port and the C++ give the same position and velocity **to the last bit** at
every step, and the same error code, with each of the three sets of constants and in both of the C++'s operation
modes, on macOS (arm64) and on Linux (x86-64).

**The epoch.** GPKit keeps an element set's epoch exactly. The C++'s own reader does not: it takes a TLE's epoch
field through a month, a day, an hour, a minute and a second and back to a Julian date, and comes out up to 20
microseconds from what the line states. Of every other element the two readers make the same doubles. So the
comparison with the C++ is made at the C++ reader's epoch, where GPKit, reading the same two lines, is identical to
it to the bit at all 2,349 steps. At the epoch the line states, GPKit's positions differ from the C++ reader's by
what its drift is worth: under half a millimetre for 32 of the 33 cases, and 4.1 mm for one, case 23333, a
deep-space orbit of eccentricity 0.97.

**Against python-sgp4**, where a gpconf corpus with its provider files is at hand: every element set of the corpus,
read by GPKit and by python-sgp4 each with its own reader, propagated to six times from the epoch to a week out.
`tools/python_sgp4_reference.py` makes python-sgp4's side and the test `CrossCheckTests` compares. CI has no corpus
and skips it. The run of 2026-10-06, against python-sgp4 2.27: 14,411 element sets, the largest difference 0.0024 mm.

**Against Skyfield**, for passes: five element sets that are already public (the Space Station's first, an old
rocket body, a fragment in an eccentric orbit, an object numbered 100000 through an Alpha-5 line, and a Molniya)
over one place for two days each. `tools/skyfield_passes_reference.py` writes Skyfield's rises, culminations and
sets to a file the tests read, so CI makes this comparison. With Skyfield 1.55: 49 passes, pass for pass; rises and
sets within 0.17 s and culminations within 0.35 s, where Skyfield's own search stops within half a second; and at
329 of Skyfield's times GPKit's elevation is within 0.005 degrees of its, the azimuth within 0.011 degrees on the
sky, the range within 85 m and the range rate within 1.3 m/s, which is under 2 Hz at 437 MHz. All of that is UT1
less UTC, which Skyfield applies and GPKit does not: with the Earth turned by Skyfield's own value for each instant
(up to 0.24 s at these dates) the two agree to a millionth of a degree, to 2 cm and to 0.0002 m/s.

The summaries of the last two are in [`conformance/`](conformance/). The C++, the verification cases and the
element sets of the pass comparison are in the repository for the tests only; [NOTICE](NOTICE) says where each comes
from and on what terms.

## Building and testing

```bash
swift build
```

```bash
swift test
```

With the Command Line Tools and no Xcode, the test build needs to be told where the testing macros are:

```bash
swift test -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing
```

The public interface, as the compiler states it, is in [`docs/public-api.swift`](docs/public-api.swift);
`tools/public-api.sh` writes it. `Propagator`, `Observer`, `Look`, `Pass`, the vector types and the arithmetic on
`Epoch` are the proposal; the rest is settled.

## Licence

MIT. See [LICENSE](LICENSE), and [NOTICE](NOTICE) for the SGP4 source the propagator is ported from and for what
the tests use from elsewhere.
