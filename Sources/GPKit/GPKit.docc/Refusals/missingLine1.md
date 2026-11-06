# ``GPKit/Refusal/Kind-swift.enum/missingLine1``

## What happened

A TLE line 2 with no line 1 before it.

## How to fix it

An element set is two lines, 1 and then 2. Line 1 was lost, or the lines were taken from the middle of a file.

## Example

Read as TLE:

```text
2 25544  51.5908 168.3788 0125362  86.4185 359.7454 16.05064833    05
```

GPKit says:

```text
a line 2 with no line 1 before it (line 1 of the file)
```
