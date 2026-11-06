# ``GPKit/Refusal/Kind-swift.enum/malformedRecord``

## What happened

A record whose structure is not the format's: a CSV row with more or fewer fields than the header, a JSON array element that is not an object, a KVN line that is not `KEYWORD = value`.

## How to fix it

In a CSV, a value holding a comma must be in quotes; one that is not shifts the fields. Otherwise the record was damaged; fetch it again.

## Example

Read as CSV:

```text
OBJECT_NAME,OBJECT_ID,EPOCH,MEAN_MOTION,ECCENTRICITY,INCLINATION,RA_OF_ASC_NODE,ARG_OF_PERICENTER,MEAN_ANOMALY,EPHEMERIS_TYPE,CLASSIFICATION_TYPE,NORAD_CAT_ID,ELEMENT_SET_NO,REV_AT_EPOCH,BSTAR,MEAN_MOTION_DOT,MEAN_MOTION_DDOT
ISS (ZARYA),1998-067A,1998-11-20T06:49:59.999808,16.05064833,.0125362,51.5908,168.3788,86.4185,359.7454,0,U,25544,1,0,0,-.3657E-4
```

GPKit says:

```text
the row has 16 fields and the header 17 (line 2 of the file)
```
