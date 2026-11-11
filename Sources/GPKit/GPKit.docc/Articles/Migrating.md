# Migrating to GPKit 2.0

Move a program written against GPKit 1.x to 2.0: one change breaks code, and the rest is added.

## Overview

GPKit 2.0 changes one thing a 1.x program can depend on: an element set for SGP4-XP is refused with a kind of its
own, ``PropagationFailure/Kind-swift.enum/sgp4XP``. Everything else in 2.0 is new, so code that does not look at
the kind of a ``PropagationFailure`` builds and runs as before.

### SGP4-XP sets have their own kind

SGP4-XP is the theory of an element set whose ephemeris type is 4, or whose `MEAN_ELEMENT_THEORY` is `SGP4-XP`.
SGP4 run on such a set gives positions that look right and are not, so GPKit has always refused it. In 1.x it was
refused as ``PropagationFailure/Kind-swift.enum/notSGP4``. In 2.0 it is refused as `.sgp4XP`, and `.notSGP4` means
a theory other than SGP4 or SGP4-XP. The set is still read as written, and the TLE writer keeps its type.

Two kinds of code need a change:

- **A `switch` over every kind with no `default`** no longer compiles. Add the case.
- **A test for `.notSGP4`** that is meant to catch every set SGP4 is not for misses SGP4-XP sets. Test for
  `.sgp4XP` too: `failure.kind == .notSGP4 || failure.kind == .sgp4XP`.

A switch with every kind handled, as 2.0 has them:

```swift
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
```

### What is new

- ``OrbitClass``, ``DataAge`` and ``DataAgeTable``: how old an element set is, and the position error to expect at
  that age, read from a measured table. GPKit ships no table yet; ``DataAge/measure(_:maximumAge:)`` makes the
  measurement from sets you hold. ``OrbitClass`` is a struct, not an enum, so a `switch` over classes needs a
  `default`: ESA's list of classes grows, and a class added later breaks nothing.

### Checking a program

Build the program against 2.0. The compiler names every exhaustive `switch` that lacks `.sgp4XP`. Then search for
`.notSGP4`: each place that means "SGP4 is not for this set" needs `.sgp4XP` beside it.
