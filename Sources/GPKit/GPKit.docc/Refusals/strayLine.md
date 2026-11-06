# ``GPKit/Refusal/Kind-swift.enum/strayLine``

## What happened

A line in a TLE file that is neither an element line nor the name of the set that follows it.

## How to fix it

A name line comes only before the set it names. Text after the last set, or a comment between sets, is refused; remove it, and the sets around it are still read.

## Example

Read as TLE:

```text
ISS (ZARYA)
1 25544U 98067A   98324.28472222 -.00003657  11563-4  00000+0 0    10
2 25544  51.5908 168.3788 0125362  86.4185 359.7454 16.05064833    05
end of file
```

GPKit says:

```text
a line that is neither an element line nor the name of the set after it (line 4 of the file)
```
