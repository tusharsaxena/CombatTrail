# Testing — Ka0s Combat Trail

How to verify the addon (documentation-§3; testing). What to install first is the root
[`DEPENDENCIES.md`](../DEPENDENCIES.md); this page assumes it is done. Every command runs from the
**repo root**.

## Commands

| Command | What it does |
|---|---|
| `lua tests/run.lua` | The headless suite under the Retail kit profile. Exits non-zero on any failure |
| `KA0S_KIT_CLIENT=forever lua tests/run.lua` | The same suite under the WoW Forever profile (clients-§6) |
| `lua tests/run.lua -j auto` | The same, split across one worker per CPU (testing-§14) |
| `lua tests/run.lua --list > docs/test-cases.md` | Regenerates the case inventory without running anything |
| `~/.claude/dev-copilot/bin/ka0s-bounded luacheck .` | Lint, configured by `.luacheckrc`; must report 0 warnings and 0 errors. `luacheck` loads no kit, so it runs through the bounded runner (testing-§15) |
| `~/.claude/dev-copilot/bin/ka0s-bounded lizard -C 15 -x "./libs/*" -x "./tests/_kit/*" .` | Complexity: no function above CCN 15 |
| `luac -p path/to/file.lua` | Syntax-check one file |
| `bash tests/_kit/run-automated-tests.sh` | All four out-of-game suites, written to a dated bundle ([automated-tests/README.md](automated-tests/README.md)) |

Every suite run is bounded by the vendored kit as it loads (memory, time, process depth; testing-§15).

## The commit gate

Before **every** commit, all four must hold:

- `lua tests/run.lua` green;
- `KA0S_KIT_CLIENT=forever lua tests/run.lua` green (the addon serves both clients, so the suite runs
  under both kit profiles);
- bounded `luacheck .` at 0/0;
- `lizard -C 15` over the authored tree with no warning.

Work is test-first: a failing case that pins the behavior, then the code. The working tree is CRLF
(line-endings-§2); a file written with LF fails `test_eol` until it is converted.

## The four out-of-game suites

| Suite | Command | Gates the commit? | Gates the release (tag)? |
|---|---|---|---|
| `lint` | `~/.claude/dev-copilot/bin/ka0s-bounded luacheck .` | yes | yes |
| `tests` | `lua tests/run.lua` (both profiles) | yes | yes |
| `perf` | `lua tests/perf.lua` (not written yet, so a skip) | no, recorded only | yes, at `pass`; a skip is not evaluated |
| `complexity` | `bash tests/_kit/run-automated-tests.sh --suite complexity` | no, recorded only (the commit gate runs lizard directly) | yes, at `pass` with zero functions above CCN 15 |

## How the harness works

- `tests/run.lua` builds one isolated instance per `loadInstance(opts)`: a fresh client mock
  (`tests/wow_mock.lua` on the kit's `mock_*` files), the vendored LibKa0s files read out of
  `LibKa0s.xml` in its own order, the addon's files read out of `CombatTrail.toc`, then
  `OnInitialize` and `OnEnable`. The runner cannot drift from what the client loads.
- `_G.CT_TEST` is the suite's handle: `T.NS`, `T.mocks`, `T.load(opts)`, the secret helpers
  (`T.secret`, `T.isSecret`, `T.reveal`) and `T.mockMeter`, the scripted `C_DamageMeter`
  (`tests/mock_meter.lua`).
- The suites start from a player who has seen the skin picker; `T.load({ loginPicker = true })`
  keeps it unseen.
- `KA0S_KIT_CLIENT=forever` loads the kit's WoW Forever client globals, so `NS.Compat.IsForever()`
  answers true and every Retail-only feature must be absent. Each per-client feature has a present
  test and an absent test.
- The kit's own gates run as suites too: line endings, the US-English prose gate, the 1500-line cap,
  lizard's sighted parity, client globals, the diagnostics contract, the skin switch and the skin
  values. `tests/test_docs.lua` holds the doc set to the code.

## Where the counts live

- [`test-cases.md`](test-cases.md) is the generated inventory and the authoritative pass count. The
  README's Tests badge carries its Total, and `tests/test_docs.lua` fails when they differ.
- [`smoke-tests.md`](smoke-tests.md) is the in-game suite the owner runs; an agent never marks a row
  passed.
- [`automated-tests/README.md`](automated-tests/README.md) is the record of the four suites over time.
