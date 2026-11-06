# ``GPKit/Refusal/Kind-swift.enum/emptyInput``

## What happened

There was nothing to read: the input is empty, or holds nothing but spaces and line endings.

## How to fix it

Look at where the input came from. A download that failed, or a file that was never written, gives nothing. A provider's own answer for "no data", such as CelesTrak's `No GP data found`, is not this: it is read as a file with no element sets, and ``ElementSetFile/providerMessage`` holds it.

## Example

Read as TLE:

```text

```

GPKit says:

```text
the input is empty
```
