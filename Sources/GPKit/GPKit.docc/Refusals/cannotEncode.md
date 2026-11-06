# ``GPKit/Refusal/Kind-swift.enum/cannotEncode``

## What happened

Writing a TLE, a value the format cannot carry: a catalog number above 339999, or a field wider than its columns.

## How to fix it

A TLE's columns hold catalog numbers up to 339999. Keep a larger one as OMM, which GPKit reads and which carries nine digits.

## Example

Read as JSON and written as a TLE:

```text
[{"OBJECT_NAME":"ISS (ZARYA)","OBJECT_ID":"1998-067A","EPOCH":"1998-11-20T06:49:59.999808","MEAN_MOTION":16.05064833,"ECCENTRICITY":0.0125362,"INCLINATION":51.5908,"RA_OF_ASC_NODE":168.3788,"ARG_OF_PERICENTER":86.4185,"MEAN_ANOMALY":359.7454,"EPHEMERIS_TYPE":0,"CLASSIFICATION_TYPE":"U","NORAD_CAT_ID":340000,"ELEMENT_SET_NO":1,"REV_AT_EPOCH":0,"BSTAR":0,"MEAN_MOTION_DOT":-3.657e-5,"MEAN_MOTION_DDOT":1.1563e-5}]
```

GPKit says:

```text
catalog number 340000 is above 339999, the most a TLE's five columns can carry; it needs an OMM
```
