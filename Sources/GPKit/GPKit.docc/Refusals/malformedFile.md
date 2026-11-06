# ``GPKit/Refusal/Kind-swift.enum/malformedFile``

## What happened

The input as a whole is not what its format requires: JSON that does not parse, XML that is not well formed, a CSV with no header row.

## How to fix it

Check that the format you named is the file's: a JSON file read as CSV is refused this way. If it is, the file is damaged; fetch it again.

## Example

Read as JSON:

```text
[{"OBJECT_NAME" "ISS (ZARYA)"}]
```

GPKit says:

```text
not JSON at byte 17: where a colon should follow a key
```
