# Profiles — Ka0s Combat Trail

How AceDB profiles work here (documentation-§3, Tier 2: the Profiles page ships in the options UI).

## What a profile holds

Everything under `CombatTrailDB.profiles[<name>]`: the master switches, both lanes, the DPS HUD, the
recording filters and retention, the Results window's view, place and look, the player's own training
dummies (`dummies.custom`, History > Training dummies) and the skin (`defaults/Profile.lua`,
[`schema.md`](schema.md)). The race call-out's look and voice are the profile's `callout` table
(Retail), seeded from its schema rows and read through the instance at every call; every write to it
goes through `NS.SetByPath`, so it is per profile like every other setting. Its words are the addon's:
no profile holds a stock text or a mute (callout plan row C11). Schema 3 migrated every stored
profile's `callout` table once (`docs/schema.md`, Migrations): a retired Off / Soft / Strong glow became
the glow's keys (its intensity and thickness; it named no color or offset, so a migrated Soft or Strong
profile reads the defaults for those: since LibKa0s v1.102.0 a black halo with *Glow color* ticked, at
1, -1, no longer each word's kind color), stored texts and mutes were dropped, and a stored voice was kept. AceDB stores
no value equal to its default, so a profile on the old default, Female (Kathleen), whether chosen or
not, has no stored voice and now speaks with the new default, Arena John. A new character starts on the `Default` profile
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
