# ``GPKit/Refusal/Kind-swift.enum/missingKeyword``

## What happened

A keyword the record must carry is missing, or its value is empty.

## How to fix it

Every OMM record carries its epoch and its mean elements. The provider left one out, or the record was edited; fetch it again.

## Example

Read as JSON:

```text
[{"OBJECT_NAME":"ISS (ZARYA)","OBJECT_ID":"1998-067A","EPOCH":"1998-11-20T06:49:59.999808","ECCENTRICITY":0.0125362,"INCLINATION":51.5908,"RA_OF_ASC_NODE":168.3788,"ARG_OF_PERICENTER":86.4185,"MEAN_ANOMALY":359.7454,"EPHEMERIS_TYPE":0,"CLASSIFICATION_TYPE":"U","NORAD_CAT_ID":25544,"ELEMENT_SET_NO":1,"REV_AT_EPOCH":0,"BSTAR":0,"MEAN_MOTION_DOT":-3.657e-5,"MEAN_MOTION_DDOT":1.1563e-5}]
```

GPKit says:

```text
MEAN_MOTION is missing or empty (record 1 of the file)
```
