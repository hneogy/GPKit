# ``GPKit``

Read GP data, OMM and TLE, and find where a satellite is and when it passes over.

## Overview

GPKit reads element sets as OMM (CSV, JSON, XML or KVN) and as TLE with Alpha-5, with catalog numbers as plain
integers, six and nine digits included. It writes TLE, propagates with SGP4, and finds passes over a place on the
ground, with the Doppler shift a radio needs.

To start, follow <doc:Tutorials>: your first pass of the Space Station, a pass drawn on a sky chart, and Doppler for
your radio.

## Topics

### Essentials

- <doc:Concepts>

### Reading

- ``ElementSets``
- ``ElementSet``
- ``TLE``
- ``Refusal``

### Propagating

- ``Propagator``
- ``Epoch``

### Passes and Doppler

- ``Observer``
- ``Pass``
- ``Passes``
- ``Look``

### Sunlight and visibility

- ``Sun``
- ``Sunlight``
- ``PassVisibility``
- ``EquatorialPosition``

### Close approaches

A rough screen on GP data with SGP4: candidate approaches with miss distance and time, not collision probability or
risk. GP data is roughly kilometre-level, so the screen is not for operational collision avoidance, and no approach
found does not mean the objects are safe.

- ``CloseApproach``

### Ephemerides

- ``OEM``

### Rotators

- ``RotatorLimits``
- ``RotatorPoint``

### Frames and maps

- ``GroundTrack``
- ``GeodeticPosition``
