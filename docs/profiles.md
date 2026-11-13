# Profiles — Ka0s Combat Trail

How AceDB profiles work here (documentation-§3, Tier 2: the Profiles page ships in the options UI).

## What a profile holds

Everything under `CombatTrailDB.profiles[<name>]`: the master switches, both lanes, the DPS HUD, the
recording filters and retention, the Results window's view, place and look, the player's own training
dummies (`dummies.custom`, History > Training dummies) and the skin (`defaults/Profile.lua`,
[`schema.md`](schema.md)). The race call-out's look, voice and words are the profile's `callout` table
(Retail), seeded from its schema rows and read through the instance at every call; every write to it
goes through `NS.SetByPath`, so it is per profile like every other setting. A new character starts on the `Default` profile
shared by every character (`AceDB:New(..., true)`).

## What a profile does not hold

These are global on purpose, so a profile switch never hides or moves them:

- **The fight store** (`global.fights`, `global.fightOrder`), the interned talent loadouts and the equipment sets: a fight
  belongs to the installation, and bests span characters.
- **The Usage hidden list** (`global.usage.hidden`), as it filters the global store.
- **The training-dummy captures** (`global.dummies.captures`): what the game said about each creature
  `/ct dummy` captured, data rather than a setting, as a creature is the same on every profile.
- **The minimap button** (`global.minimap`): a per-installation display preference, which survives
  Reset all settings and the General page's Defaults (launcher-§3).
- **The key bindings**, which the game keeps.

The retention settings are per profile while the store they purge is global; the purge reads the
current profile's settings (an open owner decision, recorded in the plan).

## Switching, copying, resetting

The Profiles page is AceDBOptions' own table (settings/Profiles.lua). A switch, copy or reset replaces
the whole profile, so `NS.OnProfileChanged` (core/Database.lua) runs one sequence for all three: the
first-run skin picker is closed, the new profile's skin is applied first so every frame repaints once,
the `disabled` hold is re-decided from the new `general.enabled`, the skin picker shows again on a
profile that has not seen it, and `SETTINGS_CHANGED("profile", key)` tells every module to redraw
from the new values (on Retail the race call-out re-applies its look from the new profile, `NS.Callout:Apply` in
modules/Countdown.lua: the new profile's `callout` table, its defaults filled in by AceDB). One debug line records each act.
