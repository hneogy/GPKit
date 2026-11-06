# ``GPKit/Refusal/Kind-swift.enum/notANumber``

## What happened

A numeric field or keyword whose text is not a number.

## How to fix it

The value was replaced by text, or the columns of a CSV were shifted. Check the field the message names.

## Example

Read as CSV:

```text
OBJECT_NAME,OBJECT_ID,EPOCH,MEAN_MOTION,ECCENTRICITY,INCLINATION,RA_OF_ASC_NODE,ARG_OF_PERICENTER,MEAN_ANOMALY,EPHEMERIS_TYPE,CLASSIFICATION_TYPE,NORAD_CAT_ID,ELEMENT_SET_NO,REV_AT_EPOCH,BSTAR,MEAN_MOTION_DOT,MEAN_MOTION_DDOT
ISS (ZARYA),1998-067A,1998-11-20T06:49:59.999808,sixteen,.0125362,51.5908,168.3788,86.4185,359.7454,0,U,25544,1,0,0,-.3657E-4,.11563E-4
```

GPKit says:

```text
MEAN_MOTION "sixteen" is not a number (line 2 of the file)
```
