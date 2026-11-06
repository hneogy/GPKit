# ``GPKit/Refusal/Kind-swift.enum/notAnEpoch``

## What happened

An epoch that is not a CCSDS time code, not a TLE's `YYDDD.DDDDDDDD` field, or not a date that exists.

## How to fix it

OMM epochs are written `YYYY-MM-DDThh:mm:ss`, with any fraction of a second after it; GPKit checks that the day is in its month. Check the epoch the message quotes.

## Example

Read as CSV:

```text
OBJECT_NAME,OBJECT_ID,EPOCH,MEAN_MOTION,ECCENTRICITY,INCLINATION,RA_OF_ASC_NODE,ARG_OF_PERICENTER,MEAN_ANOMALY,EPHEMERIS_TYPE,CLASSIFICATION_TYPE,NORAD_CAT_ID,ELEMENT_SET_NO,REV_AT_EPOCH,BSTAR,MEAN_MOTION_DOT,MEAN_MOTION_DDOT
ISS (ZARYA),1998-067A,1998-11-31T06:49:59,16.05064833,.0125362,51.5908,168.3788,86.4185,359.7454,0,U,25544,1,0,0,-.3657E-4,.11563E-4
```

GPKit says:

```text
the epoch's day 31 is not a day of month 11 of 1998 in "1998-11-31T06:49:59" (line 2 of the file)
```
