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

The element set used is Vallado's set 00005 (Vanguard 1), read at run time from SGP4-VER.TLE: the package's test
resource, or the file GPKIT_SGP4_VER_TLE names. Its two lines are held to a SHA-256, so this check runs on the same
set wherever the file comes from. No line of the file is written here.
"""
import datetime
import decimal
import hashlib
import json
import os
import subprocess
import sys

SGP4_VER = os.environ.get("GPKIT_SGP4_VER_TLE") or os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "..", "Tests", "GPKitTests", "Resources", "SGP4-VER.TLE")
SET_SHA256 = "b2285e2be534dc6d0e02c6b708ffe7d062a638017158f51550cee4e999e2727d"  # lines 1 and 2, 69 columns, LF


def the_set(path):
    """Set 00005's two lines from SGP4-VER.TLE, to column 69 (the file adds Vallado's run columns after line 2)."""
    try:
        with open(path, encoding="ascii") as f:
            lines = [line.rstrip("\r\n") for line in f]
    except OSError as error:
        print("NOT RUN: SGP4-VER.TLE is needed for the element set (%s)" % error)
        sys.exit(2)
    one = [line[:69] for line in lines if line.startswith("1 00005")]
    two = [line[:69] for line in lines if line.startswith("2 00005")]
    if len(one) != 1 or len(two) != 1 or hashlib.sha256((one[0] + "\n" + two[0]).encode()).hexdigest() != SET_SHA256:
        print("NOT RUN: %s does not hold set 00005 as this check knows it" % path)
        sys.exit(2)
    return one[0], two[0]


def record_of(line1, line2):
    """The set as a written record's fields, its four integers left as %s for the checks to fill."""
    year = 1900 + int(line1[18:20]) if int(line1[18:20]) >= 57 else 2000 + int(line1[18:20])
    day = decimal.Decimal(line1[20:32])
    micro = int((day - int(day)) * 86400 * 1000000)
    epoch = datetime.datetime(year, 1, 1) + datetime.timedelta(days=int(day) - 1, microseconds=micro)
    bstar = decimal.Decimal("0." + line1[54:59]) * decimal.Decimal(10) ** int(line1[59:61])
    designator = line1[9:17].strip()
    fields = {
        "norad_cat_id": "%s", "object_name": "VANGUARD 1",
        "object_id": "%s-%s" % (1900 + int(designator[:2]) if int(designator[:2]) >= 57 else 2000 + int(designator[:2]),
                                designator[2:]),
        "epoch": epoch.isoformat(timespec="microseconds"), "mean_motion": line2[52:63].strip(),
        "eccentricity": "0." + line2[26:33], "inclination": line2[8:16].strip(),
        "ra_of_asc_node": line2[17:25].strip(), "arg_of_pericenter": line2[34:42].strip(),
        "mean_anomaly": line2[43:51].strip(), "bstar": format(bstar, "f"),
        "mean_motion_dot": "0" + line1[33:43].strip(), "mean_motion_ddot": "0", "ephemeris_type": "%s",
        "classification_type": line1[7], "element_set_no": "%s", "rev_at_epoch": "%s",
    }
    return "{" + ", ".join('"%s": %s' % (k, v if v == "%s" else json.dumps(v)) for k, v in fields.items()) + "}"


LINE1, LINE2 = the_set(SGP4_VER)
RECORD = record_of(LINE1, LINE2)


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


    # integers sent as JSON strings: plain decimal digits, or integral decimal text, as numbers are; every other form
    # refused with an error; a "-" read, and then refused by the field's own range check, not as text
    for text in ['"100000"', '"100000.0"', '"1e5"']:
        code, answer = vectors(adapter, "alpha5_encode", text)
        if code != 0 or answer.get("result") != "A0000":
            fail("alpha5_encode %s gave %r, not A0000" % (text, answer))
    for number in ['"5"', '"5.0"', '"0005"']:
        done = call(adapter, ["write"], RECORD % (number, "0", "475", "41366"))
        if done.returncode != 0 or done.stdout != base.stdout:
            fail("norad_cat_id %s did not write as 5: %r" % (number, done.stdout + done.stderr))
    forms = {"hex": "0x%s", "octal": "0o%s", "binary": "0b%s", "plus": "+%s", "underscore": "%s_0",
             "space before": " %s", "space after": "%s ", "tab before": "\\t%s"}
    for form, shape in forms.items():
        for op, value in [("alpha5_encode", "100000"), ("two_digit_year", "57")]:
            text = '"%s"' % (shape % value)
            code, answer = vectors(adapter, op, text)
            if code == 0 or "error" not in answer:
                fail("%s %s (%s) was not refused: %r" % (op, text, form, answer))
        for field in range(4):
            fields = ["5", "0", "475", "41366"]
            fields[field] = '"%s"' % (shape % ("1" if field < 2 else fields[field]))
            done = call(adapter, ["write"], RECORD % tuple(fields))
            if done.returncode == 0 or b"is not a whole number" not in done.stderr:
                fail("write %r (%s) was not refused as not a whole number: %r" % (fields, form, done.stdout + done.stderr))
    print("met: integers as text: digits and integral decimals read; hex, octal, binary, a leading +, underscores and"
          " surrounding whitespace refused in alpha5_encode, two_digit_year and every integer field of write")
    code, answer = vectors(adapter, "alpha5_encode", '"-5"')
    if code == 0 or "is not a whole number" in answer.get("error", ""):
        fail('alpha5_encode "-5" was not read and then refused by its range: %r' % answer)
    done = call(adapter, ["write"], RECORD % ('"-5"', "0", "475", "41366"))
    if done.returncode == 0 or b"is not a whole number" in done.stderr:
        fail('write norad_cat_id "-5" was not read and then refused by its range: %r' % (done.stdout + done.stderr))
    print('met: "-5" is read as -5 and refused by the range check, in alpha5_encode and in write')

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(2)
    main(sys.argv[1])
