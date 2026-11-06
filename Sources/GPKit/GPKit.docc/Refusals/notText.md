# ``GPKit/Refusal/Kind-swift.enum/notText``

## What happened

An international designator or a classification that a TLE's columns cannot hold as written.

## How to fix it

The classification is one uppercase letter, U, C or S; the international designator is a two-digit year, a three-digit launch number and up to three letters. Check the field the message names.

## Example

Read as TLE:

```text
1 25544u 98067A   98324.28472222 -.00003657  11563-4  00000+0 0    10
2 25544  51.5908 168.3788 0125362  86.4185 359.7454 16.05064833    05
```

GPKit says:

```text
the classification "u" is not an uppercase letter (line 1 of the file)
```
