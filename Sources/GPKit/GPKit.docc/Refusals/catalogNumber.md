# ``GPKit/Refusal/Kind-swift.enum/catalogNumber``

## What happened

A catalog number that cannot be read: a TLE field that is neither five digits nor Alpha-5 (a letter and four digits), a `NORAD_CAT_ID` that is not an integer of up to nine digits, or two catalog fields of one set that differ.

## How to fix it

In a TLE, numbers up to 99999 are five digits and 100000 to 339999 are Alpha-5, where the letter stands for the first two digits (A is 10). Larger numbers do not fit a TLE: read that satellite as OMM.

## Example

Read as TLE:

```text
1 A+123U 98067A   98324.28472222 -.00003657  11563-4  00000+0 0    16
2 A+123  51.5908 168.3788 0125362  86.4185 359.7454 16.05064833    01
```

GPKit says:

```text
the catalog field "A+123" is neither five digits nor a letter and four digits (line 1 of the file)
```
