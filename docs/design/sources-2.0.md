# GPKitSources in 2.0: design

A note for the owner's review (2026-11-10), on branch `v2-sources`. GPKitSources shipped in 1.1.0 (#21) with
CelesTrak's GP queries, SatNOGS DB's transmitters, the two-hour `Ledger`, the `AnswerCache` and a `Transport` with a
recorded stand-in. 2.0 adds what a program needs between fetches, and makes no new request of anyone.

## What is added

- **ElementSetStore** (an actor): what a program holds, by catalog number. A merge orders sets by epoch, so answers
  can come in any order. It keeps the newest set as current and up to `keep` sets in all, so an older set is there
  to compare with: propagating an old set forward against a newer one is how the data-age estimate is measured
  (roadmap 2.0-c). It decides nothing a provider has not said: another set at a held epoch is reported as a
  conflict, and the held one is kept. A set with no catalog number is not held. It saves to OMM JSON in CelesTrak's
  form, numbers in their own digits, read back by GPKit's own reader, so no new format is invented.
- **FolderSource**: answers kept from earlier fetches, or captures made elsewhere, read from a folder by extension.
  Nothing is asked, so no rule applies.
- **Ledger.nextAsk**: when a program may next ask an address, so it can schedule a fetch instead of being told
  `tooSoon`. `fetch` still decides.

## What is not added, and why

- **Space-Track**: left out by the owner's ruling for 1.1.0. It needs the user's own login, and this work never
  handles credentials. The question is in the handoff.
- **SatNOGS DB's element sets**: its TLE endpoint has not been read for its rules, and no request is made to read
  it. That waits for the owner.
- **Background refresh**: a timer that fetches by itself would be GPKitSources making requests of its own. A program
  reads `stale` and `nextAsk` and calls `fetch` itself.

## How it is proved

`Tests/GPKitSourcesTests/StoreTests.swift`, ten tests, uses the recorded fixtures in
`Tests/GPKitSourcesTests/Resources/fixtures`, which are made up and described in their README, and
`RecordedTransport`. Seven faults were planted, and each fails the tests:

1. the epoch ignored on insertion;
2. the history not trimmed;
3. `OBJECT_ID` dropped on save;
4. no set ever found the same;
5. `nextAsk` ignoring the host;
6. hidden files read;
7. replaced and older swapped.
