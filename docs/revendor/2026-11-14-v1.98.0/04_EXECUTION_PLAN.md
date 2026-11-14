# 04 Execution plan

1. **The re-vendor** (one commit): both payloads at v1.98.0 and kit 56, the provenance line and the
   vendor paragraph's commit rolled, the icon and sound lines kept, the prune, and the stub's
   `SchemaRows` (01_DELTA, *Found at the gate*).
2. **The write route and the schema rows** (one commit): the descriptor gains `path = "callout."`,
   `set = NS.SetByPath` and the Options codec's encoder; `settings/Schema.lua` registers
   `NS.Callout:SchemaRows("callout.", { page = "race" })` and lists `callout.point` in
   `writeThrough`; the AceDB defaults for `profile.callout` are seeded from the rows. Tests first:
   every row reachable through the slash `get` / `set` path, `reset` restoring them, a drag's point
   written through `NS.SetByPath`.
3. **The settings section** (one commit): `settings/Race.lua` draws the call-out's tabs through
   `SettingsTabs` / `BuildSettings` with the addon's Options instance in path mode. Test: the
   section is built and its rows carry their paths.
4. **finalCountdown up to 20** (one commit): `Countdown.MAX`, the schema row's max, the clamp, tests
   and docs.
5. **Docs and smoke rows** (with each commit, the smoke rows RM81-RM84 and known-limitations last).
