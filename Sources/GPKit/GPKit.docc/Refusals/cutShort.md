# ``GPKit/Refusal/Kind-swift.enum/cutShort``

## What happened

The input ends inside a record, a quoted field or a structure that is still open.

## How to fix it

The file was cut off, often a download that stopped part way. Fetch it again whole.

## Example

Read as JSON:

```text
[{"OBJECT_NAME": "ISS (ZARYA)", 
```

GPKit says:

```text
the JSON ends where a key should be
```
