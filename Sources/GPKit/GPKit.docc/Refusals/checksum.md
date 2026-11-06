# ``GPKit/Refusal/Kind-swift.enum/checksum``

## What happened

The last digit of a TLE line, its checksum, is not the one the line's other characters compute to.

## How to fix it

Usually a character of the line was changed or lost on the way. Fetch the lines again. If you edited the line on purpose, read it with `checksum: .ignore`.

## Example

Read as TLE:

```text
1 25544U 98067A   98324.28472222 -.00003657  11563-4  00000+0 0    11
2 25544  51.5908 168.3788 0125362  86.4185 359.7454 16.05064833    05
```

GPKit says:

```text
line 1's checksum is 1, and the line computes to 0 (line 1 of the file)
```
