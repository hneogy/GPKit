"""pygpkit's answers held to GPKit's own, to the bit.

tests/reference.json is what GPKit itself gives for these files (python/Sources/pygpkit-reference), a release
build on macOS for arm64; CI writes it again there and stops if it differs from the one committed. Each system's C
library rounds its sines and cosines its own way, so on another system the tests are held to the reference that
system's release build of GPKit writes, named by PYGPKIT_REFERENCE. Every number is compared with ==, never with a
tolerance.

    python -m unittest discover -s tests       (from python/, with pygpkit importable)
"""

import datetime
import json
import os
import unittest

import pygpkit

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)          # python/: the reference's paths are from here

with open(os.environ.get("PYGPKIT_REFERENCE") or os.path.join(HERE, "reference.json"), encoding="utf-8") as f:
    REFERENCE = json.load(f)
OBSERVER = pygpkit.Observer(*REFERENCE["observer"])


def as_state(value):
    return pygpkit.State(tuple(value["position"]), tuple(value["velocity"]))


class TheSameAsGPKit(unittest.TestCase):

    def read(self, entry_file):
        return pygpkit.read(os.path.join(ROOT, entry_file["path"]), format=entry_file["format"])

    def each_set(self):
        for entry_file in REFERENCE["files"]:
            file = self.read(entry_file)
            self.assertEqual(len(file.entries), len(entry_file["entries"]), entry_file["path"])
            for mine, theirs in zip(file.entries, entry_file["entries"]):
                if "fields" in theirs:
                    yield mine, theirs

    def test_reading(self):
        sets = refused = 0
        for entry_file in REFERENCE["files"]:
            file = self.read(entry_file)
            for mine, theirs in zip(file.entries, entry_file["entries"]):
                if "refusal" in theirs:
                    refused += 1
                    self.assertIsInstance(mine, pygpkit.Refusal)
                    self.assertEqual(mine.kind, theirs["refusal"]["kind"])
                    self.assertEqual(str(mine), theirs["refusal"]["description"])
                else:
                    sets += 1
                    self.assertIsInstance(mine, pygpkit.ElementSet)
                    self.assertEqual(mine.fields, theirs["fields"])
                    self.assertEqual(mine.mean_motion, theirs["fields"]["mean_motion"])
        self.assertEqual((sets, refused), (6, 1))

    def test_writing_a_tle(self):
        for mine, theirs in self.each_set():
            self.assertEqual(mine.to_tle(), (theirs["tle"]["name"], theirs["tle"]["line1"], theirs["tle"]["line2"]))

    def test_states(self):
        count = 0
        for mine, theirs in self.each_set():
            propagator = pygpkit.Propagator(mine)
            for minutes, expected in zip(REFERENCE["minutes"], theirs["states_by_minute"]):
                if "failure" in expected:
                    with self.assertRaises(pygpkit.PropagationFailure) as caught:
                        propagator.state_at_minutes(minutes)
                    self.assertEqual(caught.exception.kind, expected["failure"]["kind"])
                else:
                    self.assertEqual(propagator.state_at_minutes(minutes), as_state(expected["value"]))
                count += 1
            states = propagator.states(theirs["times"])
            for state, expected in zip(states, theirs["states_by_time"]):
                self.assertEqual(state, as_state(expected["value"]))
                count += 1
        self.assertEqual(count, 6 * (len(REFERENCE["minutes"]) + 13))

    def test_looks_and_positions(self):
        for mine, theirs in self.each_set():
            propagator = pygpkit.Propagator(mine)
            for time, look, position in zip(theirs["times"], theirs["looks"], theirs["positions"]):
                self.assertEqual(propagator.look(OBSERVER, time), pygpkit.Look(**look["value"]))
                self.assertEqual(propagator.position(time), pygpkit.GeodeticPosition(**position["value"]))

    def test_passes(self):
        search = REFERENCE["pass_search"]
        total = 0
        for mine, theirs in self.each_set():
            found = pygpkit.Propagator(mine).passes(OBSERVER, start=mine.epoch, seconds=search["seconds"], above=search["above"])
            self.assertEqual(len(found), len(theirs["passes"]["passes"]), mine.object_name)
            self.assertEqual(found.failure is None, theirs["passes"]["failure"] is None)
            for p, expected in zip(found, theirs["passes"]["passes"]):
                for name in ("rise", "culmination", "set"):
                    event, want = getattr(p, name), expected[name]
                    if want is None:
                        self.assertIsNone(event)
                    else:
                        self.assertEqual(event.time, want["time"])
                        self.assertEqual(event.look, pygpkit.Look(**want["look"]))
            total += len(found)
        self.assertEqual(total, 44)


class TheInterface(unittest.TestCase):

    def iss(self):
        return pygpkit.read(os.path.join(ROOT, "..", "Examples", "data", "iss-1998.tle")).element_sets[0]

    def test_the_tutorials_first_pass(self):
        # the figures the DocC tutorial prints for the same set, place and day
        iss = self.iss()
        passes = pygpkit.Propagator(iss).passes(pygpkit.Observer(40.0, -75.0), start=iss.epoch, seconds=86_400)
        risen = [p for p in passes if p.rise is not None]
        self.assertEqual(risen[0].rise.time, "1998-11-20T14:05:39.422000")
        self.assertEqual(round(risen[0].culmination.look.elevation), 15)
        self.assertEqual(len(risen), 6)

    def test_an_aware_datetime_is_the_same_instant(self):
        propagator = pygpkit.Propagator(self.iss())
        when = datetime.datetime(1998, 11, 20, 9, 49, 59, 999808, tzinfo=datetime.timezone(datetime.timedelta(hours=3)))
        self.assertEqual(propagator.state(when), propagator.state("1998-11-20T06:49:59.999808"))
        with self.assertRaises(ValueError):
            propagator.state(datetime.datetime(1998, 11, 20, 6, 50))

    def test_bytes_and_refusals(self):
        with open(os.path.join(ROOT, "tests", "data", "iss-1998-bad-checksum.tle"), "rb") as f:
            data = f.read()
        self.assertEqual(len(pygpkit.read(data, format="tle").refusals), 1)
        # the same lines with the checksum not looked at are read
        self.assertEqual(len(pygpkit.read(data, format="tle", checksum=False).element_sets), 1)
        with self.assertRaises(ValueError):
            pygpkit.read(data)
        with self.assertRaises(pygpkit.Refusal) as caught:
            pygpkit.read(b"", format="json")
        self.assertEqual(caught.exception.kind, "emptyInput")

    def test_a_decayed_satellite_fails_with_its_reason(self):
        sets = pygpkit.read(os.path.join(ROOT, "..", "Tests", "GPKitTests", "Resources", "pass-check-sets.tle")).element_sets
        delta = next(s for s in sets if s.catalog_number == 20453)
        with self.assertRaises(pygpkit.PropagationFailure) as caught:
            pygpkit.Propagator(delta).state("2026-12-31T00:00:00")
        self.assertIn(caught.exception.kind, ("decayed", "eccentricity", "perturbedEccentricity", "semiLatusRectum", "meanMotion"))
        self.assertIsNotNone(caught.exception.minutes_from_epoch)


    def test_an_sgp4_xp_set_is_refused_with_its_own_kind(self):
        line1 = "1 20453U 90008B   26263.56914166  .00350177  49935-4  75989-3 4  999"
        line1 += str(sum(int(c) if c.isdigit() else (1 if c == "-" else 0) for c in line1) % 10)
        line2 = "2 20453  35.5934 307.3932 0022512 310.3690  49.5094 15.96788691956793"
        (s,) = pygpkit.read((line1 + "\r\n" + line2 + "\r\n").encode(), format="tle").element_sets
        with self.assertRaises(pygpkit.PropagationFailure) as caught:
            pygpkit.Propagator(s)
        self.assertEqual(caught.exception.kind, "sgp4XP")


if __name__ == "__main__":
    unittest.main()
