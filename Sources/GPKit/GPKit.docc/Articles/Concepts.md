# Concepts

Element sets, TLE and OMM, catalog numbers and Alpha-5, SGP4, and how far GPKit's results can be trusted.

## Element sets and their epoch

An element set is a short description of a satellite's orbit, measured at one moment. That moment is its epoch:
the further a time is from the epoch, the less exact the satellite's position at that time becomes. A satellite's
age is counted from its epoch, so an element set is best replaced by a newer one as it ages. In GPKit an element set
is an ``ElementSet``, its epoch an ``Epoch``, always UTC.

## TLE and OMM

A TLE, a two-line element set, is an element set written as two lines of 69 characters each. Its fields are fixed
columns, and its catalog number has room for only five digits. GPKit reads it with ``TLE`` and ``ElementSets``, and
writes it with ``TLE/write(_:eccentricity:)``.

OMM, the Orbit Mean-Elements Message, is a newer way of writing an element set, from the space agencies' standards
body, CCSDS. It labels every value, and it has room for catalog numbers past five digits. Providers serve it as CSV,
JSON, XML or KVN; GPKit reads all four.

A TLE's columns hold fewer digits than an OMM can carry, so an element set written as a TLE is brought to each
field's resolution: by default ``TLE/write(_:eccentricity:)`` rounds each value exactly in decimal, a half rounding up.

## Catalog numbers and Alpha-5

Every object in orbit gets a number when it is first tracked. The ISS is 25544. On 11 July 2026 the numbers passed
99,999, when the satellite Saramago became 100000.

A TLE has room for five digits, so numbers past 99,999 do not fit. Alpha-5 writes the first two digits as one
letter: A is 10, so 100000 is A0000. It skips I and O, so letters cannot be misread as 1 and 0. It reaches 339999.
Space-Track uses it. CelesTrak does not, and serves larger numbers as OMM instead.

In GPKit a catalog number is a plain integer whatever the input wrote, and ``Alpha5`` converts between the two.

## SGP4

SGP4 is the standard method for running an element set forward in time. It allows for the Earth's shape and the
thin air at a satellite's height. For high orbits, it adds the pull of the Sun and the Moon. It is what TLEs are
made for. In GPKit it is ``Propagator``.

## How far the results can be trusted

GPKit's results are checked against other implementations, with the records in the repository's `conformance`
folder:

- **SGP4 against SGP4.** On the verification element sets published with "Revisiting Spacetrack Report #3", the
  port agrees with David Vallado's `SGP4.cpp` within a micrometre, which the tests hold; on the builds recorded, all
  2349 steps agreed to the bit (`vallado-sgp4-2026-11-05.txt`). Over 14,411 element sets of a gpconf corpus, the
  largest difference from python-sgp4 was 0.0024 mm (`python-sgp4-crosscheck-2026-10-07.txt`).
- **Passes against Skyfield.** Over five element sets and 49 passes, rises and sets agree with Skyfield's within
  0.17 s and culminations within 0.35 s, elevations within 0.0044° and azimuths within 0.0101°
  (`skyfield-2026-10-07.txt`).
- **Reading against gpconf.** GPKit passes 17 of gpconf 0.8.0's 18 cases, and none fails; the eighteenth checks data
  and runs no parser (`gpconf-0.8.0-2026-11-05.txt`).

These say that GPKit computes what SGP4 computes. They do not say how close SGP4 comes to where the satellite truly
is: that depends on the element set and on its age, and GPKit does not yet measure it.

Two simplifications of the passes are GPKit's own. Angles are geometric, with no refraction, so near the horizon a
satellite is heard a little before its elevation here reaches zero. And UT1 is taken to be UTC, which it is to
within 0.9 s, and the motion of the pole is left out; together they move a place on the ground by under half a
kilometre.
