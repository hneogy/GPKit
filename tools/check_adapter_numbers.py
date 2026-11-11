#!/usr/bin/env python3
"""Check how the gpconf adapter reads a request's numbers, as gpconf would call it.

    python3 tools/check_adapter_numbers.py .build/debug/gpkit-gpconf

Numbers are read as the digits sent, never through a 16-digit round trip: a propagate time of 1440.0000000000002
minutes is not 1440. A whole number written with a fraction or an exponent (100000.0, 1e5, 25544.0) is still that
integer, as 1.x read it; a fractional number where an integer is expected (100000.5, 25544.5) is refused, and in a
written record never taken for an absent field. Every integer of every operation: alpha5_encode's number,
two_digit_year's year, and write's norad_cat_id, ephemeris_type, element_set_no and rev_at_epoch.
parse_catalog_id is not among them: its text goes to the library's own reader, OMM.catalogNumber, which gpconf
grades. Every check must hold; the first that does not ends the run with exit 1.
"""
import json
import subprocess
import sys

LINE1 = "1 00005U 58002B   00179.78495062  .00000023  00000-0  28098-4 0  4753"
LINE2 = "2 00005  34.2682 348.7242 1859667 331.7664  19.3264 10.82419157413667"
RECORD = ('{"norad_cat_id": %s, "object_name": "VANGUARD 1", "object_id": "1958-002B", '
          '"epoch": "2000-06-27T18:50:19.733568", "mean_motion": "10.82419157", "eccentricity": "0.1859667", '
          '"inclination": "34.2682", "ra_of_asc_node": "348.7242", "arg_of_pericenter": "331.7664", '
          '"mean_anomaly": "19.3264", "bstar": "0.000028098", "mean_motion_dot": "0.00000023", '
          '"mean_motion_ddot": "0", "ephemeris_type": %s, "classification_type": "U", "element_set_no": %s, '
          '"rev_at_epoch": %s}')


def call(adapter, args, stdin):
    return subprocess.run([adapter, *args], input=stdin.encode(), capture_output=True)


def fail(message):
    print("NOT MET: " + message)
    sys.exit(1)


def vectors(adapter, op, raw_input):
    done = call(adapter, ["vectors"], '{"op": "%s", "input": %s}' % (op, raw_input))
    return done.returncode, json.loads(done.stdout.decode() or "{}")


def main(adapter):
    # times: the digits sent, a 17-digit time apart from its 16-digit neighbour
    raw = json.dumps(LINE1 + "\n" + LINE2)
    code, answer = vectors(adapter, "propagate", '{"raw": %s, "fmt": "tle", "tsince": [1440.0000000000002, 1440]}' % raw)
    if code != 0 or len(answer.get("result", [])) != 2:
        fail("propagate did not answer two steps: %r" % answer)
    if answer["result"][0] == answer["result"][1]:
        fail("1440.0000000000002 minutes was read as 1440")
    print("met: a 17-digit time reaches the propagator as sent")

    # whole numbers in any of JSON's forms are integers; a fraction is refused
    for text in ["100000", "100000.0", "1e5", "1.0E5"]:
        code, answer = vectors(adapter, "alpha5_encode", text)
        if code != 0 or answer.get("result") != "A0000":
            fail("alpha5_encode %s gave %r, not A0000" % (text, answer))
    code, answer = vectors(adapter, "alpha5_encode", "100000.5")
    if code == 0 or "error" not in answer:
        fail("alpha5_encode 100000.5 was not refused: %r" % answer)
    print("met: alpha5_encode reads 100000, 100000.0, 1e5 and 1.0E5 alike and refuses 100000.5")

    # a two-digit year: two digits as written, or a whole two-digit number in another form; a fraction refused
    for text, year in [('"57"', 1957), ('"05"', 2005), ("57", 1957), ("57.0", 1957), ("5.7e1", 1957)]:
        code, answer = vectors(adapter, "two_digit_year", text)
        if code != 0 or answer.get("result") != year:
            fail("two_digit_year %s gave %r, not %d" % (text, answer, year))
    for text in ["57.5", "5", '"5"']:
        code, answer = vectors(adapter, "two_digit_year", text)
        if code == 0 or "error" not in answer:
            fail("two_digit_year %s was not refused: %r" % (text, answer))
    print("met: two_digit_year reads \"57\", 57, 57.0 and 5.7e1 alike, and refuses 57.5 and a one-digit 5")

    # a written record: 25544.0 is 25544, 25544.5 is refused and never written as an absent catalog number
    base = call(adapter, ["write"], RECORD % ("5", "0", "475", "41366"))
    if base.returncode != 0:
        fail("the plain record was refused: %s" % base.stderr.decode().strip())
    # every integer field alike: the catalog number, the ephemeris type, the element set number, the revolution
    whole = [("5.0", "0.0", "475.0", "41366.0"), ("5e0", "0e0", "4.75e2", "4.1366e4"), ("5", "-0.0", "475", "41366")]
    for fields in whole:
        done = call(adapter, ["write"], RECORD % fields)
        if done.returncode != 0 or done.stdout != base.stdout:
            fail("%r did not write as 5, 0, 475 and 41366: %r" % (fields, done.stdout + done.stderr))
    fractional = [("5.5", "0", "475", "41366"), ("5", "0.5", "475", "41366"), ("5", "0", "475.5", "41366"),
                  ("5", "0", "475", "41366.5")]
    for fields in fractional:
        done = call(adapter, ["write"], RECORD % fields)
        if done.returncode == 0:
            fail("%r was written, a fraction dropped: %r" % (fields, done.stdout))
    print("met: write reads 5.0, 5e0, 4.75e2 and -0.0 as integers in every integer field, and refuses a fraction in"
          " norad_cat_id, ephemeris_type, element_set_no and rev_at_epoch")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(2)
    main(sys.argv[1])
