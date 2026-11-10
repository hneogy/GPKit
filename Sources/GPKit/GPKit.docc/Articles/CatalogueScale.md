# Working with a whole catalogue

Hold tens of thousands of satellites in a bounded amount of memory: read the input a piece at a time, keep only the
propagators, and stream their states.

## Overview

A program that follows a whole catalogue or a large constellation pays for three things:
- the text it reads;
- the records GPKit reads from that text;
- the propagators.

It also pays for the states it asks for. Two habits keep all of it bounded:
- **read in pieces, keep only the propagators;**
- **stream a run of states instead of keeping it.**

The figures below are for 40,000 made-up element sets on an Apple M5, from the records in GPKit's `conformance/`
folder. Each propagator holds its ``ElementSet``, and a propagator costs **about 3 KB a set** in all. That figure is
from a real capture of 11,141 sets, a provider's supplemental GP CSV of one constellation. Made-up sets cost about
2 KB, a lower bound. The extra in real data is in the element sets' own text; the SGP4 state is the same.

| At 40,000 sets | Most memory held |
|---|---|
| The text, the file and the propagators all kept | 174 MB |
| Read in pieces, only the propagators kept, the array made at its full size | 87 to 89 MB |
| A day at one-minute steps through `states(of:from:every:count:)` | 3,386 MB |
| The same day streamed, on top of the propagators | at most 24 MB more (15 MB measured) |

### Read in pieces, keep only the propagators

Reading a whole file holds its text, and every record read from it, until the program lets them go. Reading about a
thousand records at a time and keeping only what is propagated halves the most memory held. It gives the same element
sets as reading the file whole, in the same order. Make the array of propagators at its full size if you can count
the records first. An array that grows by doubling can hold up to twice what it keeps, and with the real file above
that undid most of the saving: 59 MB at the peak, against 61 MB for reading it whole and 40 MB made at full size.
For a CSV, each piece carries the header line:

```swift
/// Propagators for every element set of a CSV, read a thousand records at a time from its lines (the header first),
/// so that neither the whole text nor every record is held at once. `expected`, the number of records if known (count
/// the lines first), makes the array at its full size: one that grows by doubling can hold up to twice what it keeps.
/// Records GPKit refuses, and sets it will not propagate, are counted in `refused`.
func propagators(fromCSVLines lines: some Sequence<String>, expected: Int = 0, piece: Int = 1000) throws -> (propagators: [Propagator], refused: Int) {
    var header: String?
    var rows: [String] = []
    var propagators: [Propagator] = []
    propagators.reserveCapacity(expected)
    var refused = 0
    func read() throws {
        guard let header, !rows.isEmpty else { return }
        let file = try ElementSets.read(([header] + rows).joined(separator: "\n"), as: .csv)
        refused += file.refusals.count
        for set in file.elementSets {
            do { propagators.append(try Propagator(set)) } catch { refused += 1 }
        }
        rows.removeAll(keepingCapacity: true)
    }
    for line in lines where !line.isEmpty {
        if header == nil { header = line; continue }
        rows.append(line)
        if rows.count == piece { try read() }
    }
    try read()
    return (propagators, refused)
}
```

The lines can come from the disk a line at a time. On Apple's platforms, `URL.lines` gives them, so the file is
never held whole. A TLE file is read the same way, a piece ending at a record's line 2.

### Stream a run of states

`Propagator.states(of:from:every:count:)` keeps every state of a run: 14.4 million for 10,000 satellites over a day
at one-minute steps. `Propagator.streamStates(of:from:every:count:budget:chunk:isolation:_:)` hands them over a
block of instants at a time instead. Each state is the same, to the bit. With the default 8 MiB budget, streaming
adds at most 24 MB on top of the propagators. A smaller `budget` holds less, at some cost in speed: with
`budget: 2 * 1_048_576`, 40,000 satellites added 5 MB, at 69 ns a state against 55.

### Measure it on your own data

GPKit's benchmark tool runs each of these in a process of its own and prints the most memory held:

```
swift run -c release --package-path tools/benchmark benchmark --memory all --count 40000
swift run -c release --package-path tools/benchmark benchmark --memory pieces --count 40000
swift run -c release --package-path tools/benchmark benchmark --memory pieces --file PATH --format csv
swift run -c release --package-path tools/benchmark benchmark --memory pieces --file PATH --format csv --unreserved
swift run -c release --package-path tools/benchmark benchmark --count 40000 --stream
```

`--memory check-pieces` checks that a file read in pieces gives what it gives whole.
