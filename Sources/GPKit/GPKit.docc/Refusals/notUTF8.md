# ``GPKit/Refusal/Kind-swift.enum/notUTF8``

## What happened

The bytes are not UTF-8 text, so they cannot be read as any of the formats.

## How to fix it

Make sure the input is the file itself, as text: not compressed, not a page of another encoding. Pass the bytes as they came, as `Data` or `[UInt8]`; GPKit reads them as UTF-8.

## Example

Read as CSV, these bytes in hexadecimal:

```text
4F FF 0A
```

GPKit says:

```text
the input is not UTF-8
```
