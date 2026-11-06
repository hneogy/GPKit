# Examples

Three small projects built on GPKit, each its own package depending on this checkout. CI builds them and runs the
command-line ones (`tools/check-examples.sh`).

- **PassPredictor**, `pass-predictor FILE LATITUDE LONGITUDE [--from TIME] [--hours N]`: the passes over a place
  of every element set in a file, OMM or TLE.
- **Doppler**, `doppler FILE LATITUDE LONGITUDE DOWNLINK_HZ [--uplink HZ] [--from TIME] [--step SECONDS]`: what to
  tune a radio to through the next whole pass.
- **SkyView**, a Mac app: paste an element set and see the next pass on a chart of the sky. It is the chart the
  "Draw a pass on a sky chart" tutorial builds.

From this folder, for one of them:

```bash
swift run --package-path PassPredictor pass-predictor data/iss-1998.tle 40 -75 --from 1998-11-20T06:49:59.999808
```

`data/iss-1998.tle` is the Space Station's first element set, of 20 November 1998, the one the tutorials use. None
of the examples downloads anything: give them a file you have.
