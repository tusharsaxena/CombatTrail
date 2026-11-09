# Dependencies — Ka0s Combat Trail

What you need installed to build, run, test or release this addon. Commands are for
**WSL2 / Ubuntu** (the collection's development environment). How to *verify* the addon once you are
set up is `docs/testing.md` (written in plan Task 5.3); this file only covers *what to install*.

Every entry says what needs it and how that is known. Anything only plausibly required is marked as
such rather than listed as a requirement.

## Runtime (in-game): what a player needs

- **World of Warcraft, Retail (Midnight) or WoW Forever.** `CombatTrail.toc` carries
  `## Interface: 120105, 16001`, one codebase for both clients (spec §3).
- **Blizzard's built-in damage meter.** Every damage number the addon shows comes from
  `C_DamageMeter`, on both clients (spec §3). The cast lanes need nothing beyond the client's own cast
  events.
- **Nothing else.** Every library is vendored under `libs/` and committed (library-stack), so the
  player installs no separate library addon. `## OptionalDeps:` names the vendored libraries for
  load ordering, not as things to download. The Ace3, LibSharedMedia, LibDataBroker and LibDBIcon
  copies are Panel Master's, the set that loads on both clients.

## Development: the contributor toolchain

| Tool | Version | Needed for | Evidence |
|---|---|---|---|
| `lua5.1` (+ `luac`) | **5.1 exactly** | the headless suite, `lua tests/run.lua` | `tests/_kit/loader.lua` sandboxes each file with `setfenv` |
| `luacheck` | any recent (verified with 1.2.0) | `~/.claude/dev-copilot/bin/ka0s-bounded luacheck .`, the other half of the commit gate | `.luacheckrc` at the repo root |
| `git` | any recent | the suite itself, and vendoring | `tests/_kit/test_eol.lua`, `test_layout_cap.lua`, `test_prose.lua` and `test_client_globals.lua` read the tracked tree through `git ls-files`; `tests/_kit/vendor_sync.lua` compares the payloads; library-stack-§7 |
| `ka0s-bounded` | from the dev-copilot plugin | every lint and long Lua run, `~/.claude/dev-copilot/bin/ka0s-bounded` | `luacheck` loads no kit, so the commit gate runs it through this runner (`CLAUDE.md`, testing-§15) |
| POSIX shell | any | the suite's `-j` workers and the kit's bounds | `tests/_kit/framework.lua` shells out through `os.execute` and `io.popen` |
| `lizard` | any recent (verified with 1.24.0) | the `complexity` suite of `tests/_kit/run-automated-tests.sh` | the runner calls `lizard` over the sighted shadow `tests/_kit/lizard_sighted.lua` builds, because `lizard` alone is blind in places in Lua (automated-tests-§3) |
| `bash` | **4.x or later** | `tests/_kit/run-automated-tests.sh`, the automated-test bundle | its shebang is `#!/usr/bin/env bash` and it declares `declare -A ST DUR NOTE`, which POSIX `sh` cannot parse |

**Lua 5.1 is a requirement, not a preference.** The harness sandboxes each source file with
`setfenv`, which was removed in 5.2. "5.2 will probably work" is false and costs an hour to
disprove.

```sh
# Lua 5.1 and luacheck
sudo apt-get update
sudo apt-get install -y lua5.1 luarocks
sudo luarocks install luacheck

# lizard: via pipx, NOT pip. Ubuntu 24.04 marks its Python EXTERNALLY-MANAGED (PEP 668),
# so `pip install lizard` fails; pipx installs it into its own venv and puts it on PATH.
sudo apt-get install -y pipx
pipx ensurepath          # then open a new shell, or: source ~/.bashrc
pipx install lizard

# verify: each of these must print a version
lua5.1 -v                # Lua 5.1.5 ...   (if `lua` is not 5.1, use lua5.1 explicitly)
luacheck --version
lizard --version
git --version
bash --version           # GNU bash 4.x or 5.x; Ubuntu ships one
```

Versions are pinned only where a version matters: `lua5.1` is hard, and `luacheck` and `lizard` are
"any recent", where a pin would be false precision. `lizard` stays "any recent" because the kit's
sighted complexity suite checks function-count parity on every run, so a version that reads
differently shows up as a blind file rather than a quiet pass.

## Release / assets

**One entry: Pillow**, and only for **regenerating** the logo. The files in `media/logos/` are
committed: `tools/make_logo.py` draws them, the editable 512x512 `combattrail.logo.png` and the
shipped `combattrail.logo.128.tga` (the TOC icon, the minimap button and the broker icon,
uncompressed 32-bit). `.pkgmeta` keeps the `.png` out of the package. **None of this group is needed
to build, run or test the addon.**

```sh
sudo apt-get install -y python3-pil     # Pillow from apt avoids the PEP 668 pip refusal
python3 tools/make_logo.py              # from the repo root
```

The icons, the fonts and the bar textures come inside the vendored LibKa0s payload;
regenerating them is that repo's job and its toolchain.

## Am I set up correctly?

```sh
lua tests/run.lua                                             # the suite: must be green
KA0S_KIT_CLIENT=forever lua tests/run.lua                     # the same under the WoW Forever profile
lua tests/run.lua -j auto                                     # the same, across CPUs (testing-§14)
~/.claude/dev-copilot/bin/ka0s-bounded luacheck .      # must be 0 warnings / 0 errors (bounded: luacheck loads no kit)
bash tests/_kit/run-automated-tests.sh --suite complexity     # the sighted complexity report (release-time)
```

`docs/testing.md` (plan Task 5.3) will say what those commands mean and when each is run.
