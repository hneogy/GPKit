# ``GPKit/Refusal/Kind-swift.enum/lineLength``

## What happened

A TLE line that is not 69 characters, or that holds a character outside printable ASCII.

## How to fix it

A TLE's fields are fixed columns, so a line one character short cannot be read. Copy the lines whole, with no character added or lost; a tab or a non-breaking space pasted in is refused too.

## Example

Read as TLE:

```text
1 25544U 98067A   98324.28472222 -.00003657  11563-4  00000+0 0    1
2 25544  51.5908 168.3788 0125362  86.4185 359.7454 16.05064833    05
```

GPKit says:

```text
line 1 is 68 characters, not 69 (line 1 of the file)
```
