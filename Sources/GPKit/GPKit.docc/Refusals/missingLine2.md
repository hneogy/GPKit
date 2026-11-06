# ``GPKit/Refusal/Kind-swift.enum/missingLine2``

## What happened

A TLE line 1 with no line 2 after it.

## How to fix it

An element set is two lines, 1 and then 2. The file was cut off, or a line was lost between them.

## Example

Read as TLE:

```text
ISS (ZARYA)
1 25544U 98067A   98324.28472222 -.00003657  11563-4  00000+0 0    10
```

GPKit says:

```text
a line 1 with no line 2 after it (line 2 of the file)
```
