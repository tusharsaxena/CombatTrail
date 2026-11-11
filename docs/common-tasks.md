# Common tasks — Ka0s Combat Trail

Recipes for the changes made most often here (documentation-§3, Tier 1). Each ends with the green
gate in [`testing.md`](testing.md): both test profiles, bounded luacheck at 0/0, and lizard with no
function above CCN 15. Write the failing test first.

## Add a setting

- Add the default to `defaults/Profile.lua`, in the block of the page it belongs to. A Retail-only
  key is added only under `NS.Compat.ForClient({ "retail" })`, so it is absent on WoW Forever.
- Add the schema row to the page file in `settings/` (`General.lua`, `Lanes.lua`, `Hud.lua` or
  `History.lua`), in its tab's group, with `default` read from `NS.defaults`. A Retail-only row
  declares `clients = { "retail" }`. A lane row goes in the Lanes page's row builder, so both lanes
  get it.
- Read it with `NS.GetSetting(path)`. React to it in the owning module's `SETTINGS_CHANGED` handler.
- Add the locale strings to `locales/enUS.lua` (US spelling; the prose gate reads them).
- If it is a look (a color, a face, a texture), it needs its `FromSkin` companion (skinning-§6) and a
  surface in `tests/skin_surfaces.lua` if it paints a new frame.
- Update `docs/settings-panel.md` and `docs/schema.md` (`tests/test_docs.lua` checks that every drawn
  row has its `| Row | Key |` line in `settings-panel.md`).

## Add a slash verb

- Add the `{ name, desc, fn }` triple to `NS.COMMANDS` in `settings/Slash.lua`, after `version` for
  a feature verb. Wrap a feature verb's handler in `feature()`, and hand its words to the owning
  module through `delegate("Module")`, which calls `NS.Module.OnVerb(rest)`.
- A verb that must answer while the addon is disabled goes in `HOST_LIVE_VERBS` too.
- If a launcher entry or key binding does the same act, call the one handler in `core/CombatTrail.lua`
  from all of them.
- Add the row to `docs/slash-dispatch.md` and name the verb in the README's Usage
  (`tests/test_docs.lua` fails until both carry it).

## Add a bus message

- Declare it in `NS.MSG` (`core/Bus.lua`) with its one sender and its payload in the comment.
- Send it with `NS.SendBus(NS.MSG.NAME, ...)`; receive it on a target from `NS.NewBusTarget`
  registered at file scope.
- Add its row to ARCHITECTURE's *Message Bus* table (`tests/test_docs.lua` checks every key). At
  eleven messages the table spills to `docs/message-bus.md`.

## Add a game event

- Register it in the module that owns it, from that module's `Sync()`, through
  `NS.SafeRegisterEvent`. Never `COMBAT_LOG_EVENT_UNFILTERED`.
- Put the module in `core/LifecycleSetup.lua`'s `MODULES` (it needs `Suspend` and `Resume`) and its
  `Sync()` in `NS.RegisterGameEvents` (`core/CombatTrail.lua`).
- A value from the event that may be secret goes through `NS.Secrets` before any test.
- Add it to ARCHITECTURE's *Event Subscriptions*.

## Add a module file

- Create `modules/Name.lua` with the namespace line first and the self-naming header under it
  (documentation-§9).
- Add it to `CombatTrail.toc` in the right group, with a LOAD-BEARING note if it reads anything at
  file scope. The runner loads the TOC, so no second list needs it.
- Add its row to `docs/module-map.md` and its name to ARCHITECTURE's *Module Map*
  (`tests/test_docs.lua` checks both).

## Add a locale string

- Add `L["The English text"] = "The English text"` to `locales/enUS.lua`, under the heading of the
  module that uses it; the key is the string, and a missing key answers itself. Use it as
  `L["The English text"]`. Player-facing copy is plain language, US spelling, no em-dash asides.

## Add a training dummy

- A player adds one for themselves with `/ct dummy add [category]` on the target, or History >
  Training dummies (modules/Dummies.lua, the profile's `dummies.custom`).
- To ship one: measure its creature ID in game (`/ct dummy capture` saves it to
  `global.dummies.captures`), then add `[id] = { name = "Name", category = "single" }, -- date, where`
  to the client's seed in `defaults/Dummies.lua` (`single`, `cleave`, `dungeoneer`, `boss` or `pvp`).
  Never guess an ID, and never assume a Retail ID holds on WoW Forever.

## Add a sim scenario

- Add a row to `Sim.SCENARIOS` in `modules/Sim.lua` (`key`, `label`, `factor`, `desc`, and `length`,
  `board` or `lost` where it differs) and its locale strings, then a case in `tests/test_sim.lua`.

## Regenerate the case inventory

- After any change to the suites: `lua tests/run.lua --list > docs/test-cases.md` (it writes CRLF),
  and set the README's Tests badge to the new Total (`tests/test_docs.lua` compares them).
