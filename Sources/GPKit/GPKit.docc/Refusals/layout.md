# ``GPKit/Refusal/Kind-swift.enum/layout``

## What happened

A character where the TLE format fixes another: a separator column that is not a space, or a line that does not begin with its number.

## How to fix it

The line has the right length but its fields have moved, or it is not a TLE line at all. Copy the lines whole, as the provider gave them.

## Example

Read as TLE:

```text
1 25544U-98067A   98324.28472222 -.00003657  11563-4  00000+0 0    11
2 25544  51.5908 168.3788 0125362  86.4185 359.7454 16.05064833    05
```

GPKit says:

```text
line 1 column 9 is "-", where the format has a space (line 1 of the file)
```
