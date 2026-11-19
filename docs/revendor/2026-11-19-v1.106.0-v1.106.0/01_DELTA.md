Delta: LibKa0s v1.106.0 -> v1.106.0 (span: v1.106.0)

# 01 Delta (span)

Written by the v1.107.0 re-vendor (`AF-RV-CT`, `2026-11-19-v1.107.0/`). v1.106.0 was vendored in
`7371d3b` (Re-vendor LibKa0s v1.106.0, Widgets minor 28: the HUD dock guards its measurements,
RangeMaster#17) with no bundle of its own.

The listing is 3h's, run from the addon's root before the v1.107.0 copy:

```sh
horizon=$(ls -1 docs/revendor | sort | head -1 | cut -c1-10)
# vendored: payload commits since the horizon, plus CLAUDE.md commits that roll the provenance line
# recorded: each bundle folder's tag
grep -vxF -f recorded.txt vendored.txt
```

Vendored since the horizon (2026-11-13): `v1.96.0 v1.98.0 v1.100.0 v1.102.0 v1.105.0 v1.106.0`.
Recorded: `v1.96.0 v1.98.0 v1.100.0 v1.102.0 v1.105.0`. Unrecorded: `v1.106.0`.
