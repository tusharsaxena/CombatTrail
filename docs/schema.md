# Schema — Ka0s Combat Trail

What the addon persists (documentation-§3, Tier 1; savedvariables). Two SavedVariables globals, both
declared in `CombatTrail.toc`: `CombatTrailDB` (AceDB, everything below) and `CombatTrailPerfDB`
(LibKa0s-Perf's capture record, written only by `/ct perf`).

Every default is written once, in `defaults/Profile.lua`. The tables below name each key and its
default; the file's comments say what each value means.

## The settings registry (architecture-§5)

- **Storage:** the profile tree under `CombatTrailDB.profiles[<name>]`, and three global rows
  (`global.usage.hidden`, the minimap button's `global.minimap.hide`, read through its inverted
  `general.minimap.shown` row).
- **The registry:** `NS.Schema`, the one array of schema rows. **Its one writer** is
  `NS.RegisterSchemaRows` (settings/Schema.lua), called at **file scope** by each page file in
  `settings/` (General, Lanes, Hud, History) as the TOC loads them, so the load pass is the TOC's own
  settings pass. `NS.SchemaForPage` filters it per page.
- **The one write seam:** `NS.SetByPath(path, value)` (settings/Schema.lua). The pages, the CLI
  (`/ct set`), the verbs (`enable`, `lock`, `lane`, `ignore`) and the launcher all write through it,
  and it sends `SETTINGS_CHANGED`. Reads go through `NS.GetSetting(path)`.

## The profile tree

| Key | Default | Page |
|---|---|---|
| `general.enabled` | `true` | General → Master controls |
| `general.locked` | `false` | General → Master controls |
| `general.hudInCombat` | `true` | General → Master controls |
| `general.fontScale` | `1` | General → Look and skin |
| `lanes.player.*`, `lanes.pet.*` | one block per lane, `lane()` in `defaults/Profile.lua` | Lanes (all seven tabs) |
| `lanes.<k>.anchor` | `{ mode, point, relPoint, x, y, target, gap, frameName }`: the Player lane free at `CENTER` 0, -200, the Pet lane docked under it | Lanes → Size and position |
| `lanes.<k>.visibility` | `{ show = "always", hideAfter = 5, where, hideMounted, hideVehicle, hidePetBattle, hideResting, alphaCombat, alphaOOC }`; `where` has no `delve` or `arena` key, and there is no `hideVehicle` or `hidePetBattle`, on WoW Forever | Lanes → Visibility |
| `lanes.<k>.ignore` | `{ [spellID] = true }` from the client's seed; a removed seed is stored as `false` | Lanes → Ignored spells |
| `hud.show`, `fadeAfter`, `holdOnMouse`, `instancesOnly`, `paceAgainst`, `paceRange`, `overCard`, `showSkipReason` | `"auto"`, `8`, `true`, `false`, `"best"`, `1.5`, `true`, `true` | DPS HUD → Behavior |
| `hud.width`, `hud.scale`, `hud.layout.*` | `300`, `1`, every part `true` | DPS HUD → Layout |
| `hud.clock.*`, `hud.figures.*` | font blocks and the boxes' colors | DPS HUD → Clock and figures |
| `hud.chart.*` | `height = 90`, `columns = 48`, bar, colors, `cooldowns = true`, `cooldownMin = 29`, `zeroLine = true` | DPS HUD → Damage chart |
| `hud.spells.*` | `rows = 8`, `rowHeight = 22`, icons, paw, bars, font | DPS HUD → Spell rows |
| `hud.window.*` | title bar, colors, footer, `strata = "MEDIUM"`, `alpha = 1` | DPS HUD → Window |
| `hud.position` | `{ point = "TOPRIGHT", relPoint = "TOPRIGHT", x = -60, y = -160 }` | DPS HUD → Window, and the title bar's drag (named state, below) |
| `history.minLength`, `bossesOnly`, `content.*` | `30`, `false`, every kind on but `scenario`; no `mplus`, `delve` or `arena` key on WoW Forever | History → Recording filters |
| `history.days`, `keepBests`, `maxFights` | `7`, `true`, `500` | History → History |
| `results.scale`, `rowHeight`, `shareTalents` | `1`, `18`, `true` | History → Results window |
| `results.view` | the saved filters, grouping and sort (`group = "board"`, `days = 7`) | (named state, below) |
| `results.window` | `{ point, relPoint, x, y, width = 920, height = 520, view = "collapsed" }` | (named state, below) |
| `skin.*` | `source = "ka0s"`, `skin = NS.DEFAULT_SKIN` (per client), scope, font, texture, `outline = "hud"`, `pickerSeen = false` | General → Look and skin |

The debug flag, test mode and the sim are session-only (`NS.State`), never stored.

## The global tree

| Key | Holds |
|---|---|
| `schemaVersion` | The settings migration stamp; `0` in the defaults so AceDB never strips it |
| `fights` | The fight store, `{ [id] = record }` |
| `fightOrder` | The store's ids, newest first |
| `loadouts` | Talent loadouts interned once, keyed by hash; a record holds the key |
| `gearSets` | Equipment sets interned once, `{ [key] = { [slot] = trimmed item string } }`, keyed by the hash of the canonical gear (`slot=item` in slot order); a record holds the key (`gearSet`). Created on first use |
| `usage.hidden` | The item IDs the Usage list never shows, comma-separated |
| `minimap` | LibDBIcon's own table, handed to `:Register` |
| `skinNotice` | The account's one-time skin notice, written by LibKa0s-Options |

## Named non-setting state (architecture-§5)

| State | Storage key | Owner | Writers |
|---|---|---|---|
| A lane's dragged place | `lanes.<k>.anchor.x` / `.y` (and `point`) | modules/LaneAnchor.lua | `dragStop` (the edit overlay's drag) through `write`; `NS.Lanes.ResetPosition` (Master controls' Reset position) |
| The HUD's place | `hud.position` | modules/Hud.lua | `savePosition` (the title bar's drag); `Hud.ResetPosition` |
| The Results window's place, size and fold | `results.window` | modules/Results.lua | `savePosition` (drag, the grip's release, the fold arrow through `Results.SetView`); `Results.ResetPosition` |
| The saved Results view | `results.view` | modules/Results_Fights.lua | `writeView` (the Save view button) |
| The fight store | `global.fights`, `global.fightOrder` | modules/Recorder.lua | `Recorder.Save`, `Recorder.Delete`, `Recorder.SetNote`; `Retention.Purge` (modules/Retention.lua) |
| Interned loadouts | `global.loadouts` | modules/Loadouts.lua | `Loadouts.Store`; `Loadouts.Sweep`, called by the purge |
| Equipment sets | `global.gearSets` | modules/Loadouts.lua | `Loadouts.StoreGear`, through `Loadouts.Recon` (PLAYER_ENTERING_WORLD, the debounced PLAYER_EQUIPMENT_CHANGED and UNIT_INVENTORY_CHANGED, the stand-up, and the pull when no set is known); `Loadouts.Sweep`, called by the purge and a delete, keeping the current set and the live fight's |
| The Usage hidden list | `global.usage.hidden` | modules/Usage.lua | `Usage.Hide`, `Usage.Unhide` and the History page's Usage tab, all through `NS.SetByPath` |
| The skin picker seen | `skin.pickerSeen`, `global.skinNotice` | core/SkinSetup.lua (LibKa0s-Options writes the notice) | the picker's close |
| The minimap button | `global.minimap` | LibDBIcon-1.0 (vendored) | its own drag; the `general.minimap.shown` row |
| The perf record | `CombatTrailPerfDB` | LibKa0s-Perf-1.0 (vendored) | `/ct perf` |

## The fight record (CT_SCHEMA 2)

Built by `Recorder.Build` after combat from plain values only; anything that came back secret is left
absent. `Recorder.CT_SCHEMA` is the record's own format version, separate from the settings stamp; a
record with a higher `schema` than this build knows is never listed.

| Field | Holds |
|---|---|
| `schema`, `id`, `t`, `duration` | format version, `time()-NNNN` id, combat entry (epoch), seconds |
| `who` | name, realm, class, specID, specName, ilvl, petName, petFamily, client. On WoW Forever also `trees` (each talent tree's points, plain) and `specIcon`; there `specID` is `"tree:<class>:<index>"`, the predominant tree (v0.2 plan A4), with its name and icon, and absent when no tree has points |
| `identity`, `boardKey` | the encounter or primary target (`targetName`, `targetCreatureID`, `targetLevel`: plain or absent, -1 a skull), where (instance, difficulty, tiers, `zone`, `subzone`), the content kind, and the key bests group by: `e:<encounter>:<difficulty>` for an encounter, `c:<creature>:<difficulty>` for a world boss, `t:<npcID>:<level or ?>:<name>:<difficulty>` for any other target (the level is the combat-entry snapshot's, so the HUD's live pace key matches), `i:<instance>:<difficulty>` for PvP against players, `n:<name>:<difficulty>` for a named target with no NPC ID; then `:k`/`:d`/`:p` for the keystone, delve tier or PvP bracket. An unknown target has none. |
| `damage`, `dps`, `meterDps` | `{ merged, player, pet }`, merged divided by duration, the meter's own figure |
| `spells` | one packed string (CastCodec); `Recorder.Spells` unpacks it to `{ spellID, total, isPet }` |
| `casts`, `cooldowns` | the packed cast list, and `{ [spellID] = ms }` for the timeline |
| `gearSet`, `stats`, `loadout`, `usage` | the key of the equipment set current at combat start (`global.gearSets`; read through `Loadouts.GearOf`, which also takes a sample fight's inline `gear`), the stats (per fight: they move with buffs), the loadout key, what was used |
| `note`, `client`, `build`, `version`, `status` | the player's note, `retail`/`forever`, the client build, the addon version, `"final"` |

A five-minute raid fight packs under 6 KB (pinned by `tests/test_record.lua`), so 500 fights stay
near 3 MB. The History page's History tab shows the count and an estimate (`Retention.EstimateBytes`).

## Migrations

`core/Database.lua` runs `STEPS` in order against `global.schemaVersion`, moving the stamp only past
a step that returned; a step marked `perProfile` runs once for every stored profile. The target is
`NS.SCHEMA_VERSION`.

| Step | From → to | Does |
|---|---|---|
| 1 | 0 → 1 | Nothing: the first release's shape |
| 2 | 1 → 2 | Empties the fight store, its order, the loadouts and the gear sets (`global.fights`, `fightOrder`, `loadouts`, `gearSets`): the v0.2 record shape, CT_SCHEMA 2. Every other account-wide key is kept |

A change to the fight record bumps `Recorder.CT_SCHEMA` and reads the older shape where it is read,
never by rewriting stored fights. The one exception is step 2: the addon was unpublished, so the v0.1
store was emptied once instead of migrated (v0.2 plan, decision D1).
